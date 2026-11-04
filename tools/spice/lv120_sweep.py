#!/usr/bin/env python3
"""LV levels at a 120 V plate supply (doc/lv_levels_120v.md): NOR2_N16 and NAND2_J2.

A case is (cell, Ea, Vn, L0, cell parts, C1 factor). The HV levels come from .op of the cell itself;
the divider R1 || C1 / R2 to Vn (R1 + R2 = RT) maps the worst HV "0" to the LV "0" L0:
    r = (L0 - Vn) / (VOL - Vn),  LV "1" (open circuit) = Vn + (VOH - Vn) * r.
C1 per grid follows the reference (3.9 pF triode/g1, 6.8 pF g3 at 470k/200k) scaled by (R2/R1) / (200/470) * k.
Transient: the chains of nor2_sweep.py / nand2_sweep.py with Ea, Vn, levels and thresholds patched in.
Thresholds are the same for every case: LV -3 V (near the switching point), HV = middle of the case's HV levels.

usage: lv120_sweep.py static | tran [cases.py]
"""
import os, re, subprocess, sys, tempfile
import numpy as np
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import nor2_sweep as NOR, nand2_sweep as NAND
NGRUN = os.path.join(HERE, "ngrun.py")
M16 = os.path.join(HERE, "..", "..", "sch", "libs", "6N16B.sub")
MZ2 = os.path.join(HERE, "..", "..", "sch", "libs", "6Zh2B.sub")
TH_LV = -3.0
RT = 670e3

def ng(text):
    fd, fn = tempfile.mkstemp(suffix=".cir"); os.write(fd, text.encode()); os.close(fd)
    o = subprocess.run(["timeout", "300", sys.executable, NGRUN, fn], capture_output=True, text=True).stdout
    os.unlink(fn); return o

def meas(o): return {k: float(v) for k, v in re.findall(r"^([\w()]+)\s+=\s+([-\d.e+]+)", o, re.M)}

# ---------- static: the gate's own output levels with its LV inputs at given voltages ----------
def gate(cell, p, t, a, b, out):
    if cell == "NOR":
        return f"X{t} {out} {a} 0 {out} {b} 0 6N16B\nRA{t} vcc {out} {p['Ra']}\n"
    return f"X{t} {out} {b} s{t} 0 {a} 6Zh2B\nRA{t} vcc {out} {p['Ra']}\nRS{t} vcc s{t} {p['Rg2']}\nVIS{t} vcc vss{t} 0\n"

def op_levels(cell, Ea, Vn, p):
    """VOH (inputs cut off) and VOL (worst 'on' state: one triode for NOR, AB=11 for NAND), plate loaded by RT to Vn;
    inputs: 'on' grids held by a stiff +0.4 V (clamp), 'off' grids at -20 V; also currents and dissipation."""
    inc = M16 if cell == "NOR" else MZ2
    res = {}
    for st, (va, vb) in {"off": (-20, -20), "on": (0.4, -20) if cell == "NOR" else (0.4, 0.4),
                          "10": (0.4, -20)}.items():
        if cell == "NOR" and st == "10": continue
        mm = p.get('M', '')
        s = f"* op\n.include {inc}\nVCC vcc 0 {Ea}\nVNB nb 0 {Vn}\nVA a 0 {va}\nVB b 0 {vb}\n"
        if cell == "NOR":
            s += f"X1 y a 0 y b 0 6N16B\nVIA vcc ya 0\nRA ya y {p['Ra']}\n"
        else:
            s += f"X1 y b s 0 a 6Zh2B {mm}\nVIA vcc ya 0\nRA ya y {p['Ra']}\nVIS vcc sa 0\nRS sa s {p['Rg2']}\n"
        s += f"RL y nb {RT}\n.control\nop\nprint v(y) i(VIA)" + (" v(s) i(VIS)" if cell != "NOR" else "") + "\n.endc\n.end\n"
        m = meas(ng(s)); y = m["v(y)"]; ira = m["i(via)"]; ia = ira - (y - Vn) / RT
        r = dict(Y=y, Ia=ia * 1e3, Pa=y * ia)
        if cell != "NOR":
            ig2 = m["i(vis)"]; us = m["v(s)"]; r.update(Ug2=us, Ig2=ig2 * 1e3, Ik=(ia + ig2) * 1e3, Pg2=us * ig2)
        res[st] = r
    return res

def divider(VOH, VOL, Vn, L0):
    """L0 = None: the reference divider 470k / 200k; L0 = (R1, R2): a fixed divider"""
    if isinstance(L0, tuple):
        R1, R2 = L0; r = R2 / (R1 + R2)
    else:
        r = 200 / 670 if L0 is None else (L0 - Vn) / (VOL - Vn)
        R2 = RT * r; R1 = RT - R2
    return dict(r=r, R1=R1, R2=R2, LV1=Vn + (VOH - Vn) * r)

def vtc(cell, Ea, Vn, p, d, which="A"):
    """LV input swept (the other input high = clamped +0.4 V for NAND), output plate loaded by its divider and 4 grids.
    Returns VIL: the first input voltage where the LV->LV gain (dY/dVin * r) reaches -1."""
    inc = M16 if cell == "NOR" else MZ2
    s = f"* vtc\n.include {inc}\nVCC vcc 0 {Ea}\nVNB nb 0 {Vn}\nVIN a 0 -25\nVHI h 0 0.4\n"
    if cell == "NOR":
        s += f"X1 y a 0 y off 0 6N16B\nVOFF off 0 -25\nRA vcc y {p['Ra']}\n"
    else:
        g1, g3 = ("a", "h") if which == "A" else ("h", "a")
        s += f"X1 y {g3} s 0 {g1} 6Zh2B\nRA vcc y {p['Ra']}\nRS vcc s {p['Rg2']}\n"
    s += f"R1 y yl {d['R1']:.0f}\nR2 yl nb {d['R2']:.0f}\n"
    for i in range(2):
        s += (f"XL{i} pl{i} yl 0 pl{i} yl 0 6N16B\nRAL{i} vcc pl{i} {p['Ra']}\n" if cell == "NOR"
              else f"XL{i} pl{i} yl sl{i} 0 yl 6Zh2B\nRAL{i} vcc pl{i} {p['Ra']}\nRSL{i} vcc sl{i} {p['Rg2']}\n")
    fn = tempfile.mktemp(suffix=".txt")
    s = s.replace(".include", ".include", 1) + f".control\ndc VIN -25 2 0.05\nwrdata {fn} v(y)\n.endc\n.end\n"
    s = s.replace(f".include {inc}", f".include {inc}" + ("" if cell == "NOR" else f"\n.include {M16}"))
    ng(s); dd = np.loadtxt(fn); os.unlink(fn)
    vin, y = dd[:, 0], dd[:, 1]; g = np.gradient(y, vin) * d['r']
    return vin[np.where(g <= -1)[0][0]]

# ---------- transient: patch the reference decks ----------
def patch(text, Ea, Vn, VH, VL, th_hv):
    out = []
    for l in text.splitlines():
        if l.startswith("VCC vcc 0"): l = f"VCC vcc 0 {Ea}"
        elif l.startswith("VNB nb 0"): l = f"VNB nb 0 {Vn}"
        elif l.startswith(("VSA", "VSB")):
            l = " ".join({"150": f"{VH}", "50": f"{VL}", "150)": f"{VH})", "50)": f"{VL})"}.get(w, w) for w in l.split(" "))
        l = l.replace("val=100", f"val={th_hv:.1f}").replace("val=-5", f"val={TH_LV}")
        out.append(l)
    return "\n".join(out) + "\n"

def setup(case):
    name, cell, Ea, Vn, L0, parts, k = case
    lv = op_levels(cell, Ea, Vn, parts)
    VOH, VOL = lv["off"]["Y"], lv["on"]["Y"]
    d = divider(VOH, VOL, Vn, L0)
    sc = (d['R2'] / d['R1']) / (200 / 470) * k
    p = dict(parts, R1=f"{d['R1']:.0f}", R2=f"{d['R2']:.0f}")
    p.setdefault('C1g', round(3.9 * sc, 2))
    if cell == "NAND": p.setdefault('C1g3', round(6.8 * sc, 2)); p.setdefault('Cb', 15)
    if cell == "NOR": p.setdefault('L', '680u'); p.setdefault('Rd', '10k')
    return lv, d, p, VOH, VOL

def tran_job(arg):
    case, n = arg
    name, cell, Ea, Vn, L0, parts, k = case
    lv, d, p, VOH, VOL = setup(case)
    mod = NOR if cell == "NOR" else NAND
    th = (VOH + VOL) / 2
    o = ng(patch(mod.deck(p, n), Ea, Vn, VOH, VOL, th))
    return case, n, d, p, meas(o)

def fmt_tran(case, n, d, p, m):
    name, cell = case[0], case[1]
    g = lambda k, s=1: m.get(k, float('nan')) * s
    if cell == "NOR":
        return (f"{name:22s} N={n:2d} | HV {g('voh'):5.1f}/{g('vol1'):4.1f}/{g('vol2'):4.1f} | LV {g('lvl'):5.1f}/{g('lvh'):4.2f}"
                f" gridmin {g('gmin'):5.1f} ymin {g('ymin'):5.1f} | tpHL {g('tphl',1e9):4.0f} tpLH {g('tplh',1e9):4.0f}"
                f" | LV->LV {g('lvd_hl',1e9):4.0f}/{g('lvd_lh',1e9):4.0f} ns | Icc {g('icc',-1e3):5.1f} mA")
    ys = [g(f"y{i}") for i in range(len(NAND.SEQ_A))]
    lo = [y for y, a, b in zip(ys, NAND.SEQ_A, NAND.SEQ_B) if a and b]
    hi = [y for y, a, b in zip(ys, NAND.SEQ_A, NAND.SEQ_B) if not (a and b)]
    return (f"{name:22s} N={n:2d} | HV {min(hi):5.1f}/{max(lo):4.1f} haz {g('haz'):5.1f} | LV {g('lvl'):5.1f}/{g('lvh'):4.2f}"
            f" min a {g('amin'):5.1f} b {g('bmin'):5.1f} y {g('ymin'):5.1f} | tpHL a/b {g('tphl_a',1e9):4.0f}/{g('tphl_b',1e9):4.0f}"
            f" tpLH a/b {g('tplh_a',1e9):4.0f}/{g('tplh_b',1e9):4.0f} | LV->LV {g('lv_hl',1e9):4.0f}/{g('lv_lh',1e9):4.0f} ns")

def static_job(case):
    name, cell, Ea, Vn, L0, parts, k = case
    lv, d, p, VOH, VOL = setup(case)
    vil = vtc(cell, Ea, Vn, parts, d, "A")
    vil3 = vtc(cell, Ea, Vn, parts, d, "B") if cell == "NAND" else float('nan')
    return case, lv, d, p, vil, vil3

def fmt_static(case, lv, d, p, vil, vil3):
    name, cell, Ea, Vn, L0 = case[:5]
    L0x = Vn + (lv["on"]["Y"] - Vn) * d["r"]
    L0 = L0x
    on = lv["on"]; s = (f"{name:22s} | VOH {lv['off']['Y']:5.1f} VOL {on['Y']:4.1f} | r {d['r']:.3f} R1 {d['R1']/1e3:4.0f}k R2 {d['R2']/1e3:4.0f}k"
                        f" C1g {p['C1g']:.2f}" + (f"/{p['C1g3']:.2f}" if cell == "NAND" else "") +
                        f" | LV '1' open {d['LV1']:5.1f} '0' {L0x:5.1f} | VIL A {vil:5.1f} (margin {vil-L0x:4.1f})")
    if cell == "NAND":
        t = lv["10"]
        s += (f" B {vil3:5.1f} (margin {vil3-L0x:4.1f}) | 11: Ik {on['Ik']:4.1f} Pa {on['Pa']:.2f} Pg2 {on['Pg2']:.2f} Ug2 {on['Ug2']:4.0f}"
              f" | 10: Ik {t['Ik']:4.1f} Pg2 {t['Pg2']:.2f}")
    else:
        s += f" | on: Ia {on['Ia']:4.1f} mA Pa {on['Pa']:.2f} W"
    return s

REF_NOR = dict(Ra="10k")
REF_NAND = dict(Ra="15k", Rg2="15k", Cb=15)
CASES = [("NOR 150 ref", "NOR", 150, -50, None, REF_NOR, 1.0),
         ("NAND 150 ref", "NAND", 150, -50, None, REF_NAND, 1.0)]
GRIDS = (2, 6, 10)
if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "static"
    if len(sys.argv) > 2: exec(open(sys.argv[2]).read())
    with Pool(min(16, os.cpu_count())) as pool:
        if mode == "static":
            for r in pool.map(static_job, CASES): print(fmt_static(*r))
        else:
            for r in pool.map(tran_job, [(c, n) for c in CASES for n in GRIDS]): print(fmt_tran(*r))
