#!/usr/bin/env python3
"""Dekatron module SPICE testbench (sch/logic/DEKATRON_A110/README.md).

One decade as on the module board: A110 (sch/libs/A110.sub) with Ra from +E; every main cathode
through Rk to its write node Bi; a 6N16B triode (write tube) from Bi to -EK; Bi pulled up by Rp to
the rail VP; write-tube grid held at its cathode by Rc and closed by a falling HV edge through Cc
(driver: HV gate output +150 / +50 through RW). Each read line Ki has CL wiring capacitance and drives NLOAD
grids of 6N16B triodes (gate inputs, cathode on ground, plate 10k to +150): READ=div through R1 || C1
(RD1, CD1) with R2 (RD2) to ground, READ=grid straight on the line.
Guides after Yablonsky fig. 3-1 / 3-4 / 4-8: key GUIDE_EN_J2 = 6Zh2B (g1 GuideA/B, g3 En, both from
HV through 470k / 200k to -50; g2 15k to +150; cathode on ground; plate RKEY to VKEY) -> CP -> guide
ring; guide bias USM through RSM from a stiff bias node; DIODE=1 adds half a 6Kh7B across RSM
(plate on the guide, cathode on the bias node: DC restorer).

Jumper configurations (CFG): full = a write tube on each cathode; r0 = tube on K0 + one tube on the
common return of K1..K9; r09 = tubes on K0, K9 and the common return of K1..K8.

READ=diode (default): the gate grid is pulled to ground by RPU and joined to the line through half a
6Kh7B (plate on the grid node): a lit line (> 0 V) blocks the diode, an unlit one pulls the grid down;
a closed line (write) is isolated. VKEY / VKW: key plate rail idle / during a write (guide lift).
READ=cath: the read node is the write tube's cathode, Rs (RS) to -EK, the tube grid returned
to it through Rc; the line itself carries no load (doc: the write needs a line without a sink).

Commands (NAME=value overrides any default in DEF):
  seq                   operation sequence vs the RTL ring model, read lines checked at the end of each slot
  levels                static levels: read lines, write nodes, tube currents, guide bias and pulse
  count [N]             N back-to-back +1 at 100 kHz, guide bias drift (default 30)
  sweep NAME v1 v2 ...  run `seq` (or TEST=count) for each value of NAME, in parallel
  wtime                 write: minimum W width and the time to the target's current, near and far target
  plot [file.png]       waveforms: write, +1, -1 (default sch/logic/DEKATRON_A110/img/dek_module_spice.png)
"""
import os
import subprocess
import sys
import tempfile
from multiprocessing import Pool

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
LIBS = os.path.abspath(os.path.join(HERE, "..", "..", "sch", "libs"))
IMG = os.path.abspath(os.path.join(HERE, "..", "..", "sch", "logic", "DEKATRON_A110", "img"))

DEF = dict(E=350, RA="200k", CW="3p", RK="33k", RP="62k", VP=150, EK=50, CC="100p", RC="1Meg",
           RW="10k", CL="30p", NLOAD=2, READ="diode", RS="30k", RPU="100k", VPU=5, CDR="5p", CB="0.1p", CKA="0.1p", CDS="0", RK1="33k", RK2="33k", RD1="1Meg", RD2="2.2Meg", CD1="22p", USM=20, RSM="100k", CP="220p", RKEY="10k", VKEY=50, VKW=150,
           DIODE=0, CFG="full", PW=600e-9, OV=50e-9, WRW=5e-6, SLOT=10e-6, PD=3.3e-6, EN=1)
T0 = 60e-6           # power-up and settling before the first slot
VIL, VSW = -7.6, -2.2  # NOR2_N16 LV input: VIL and switching point


def val(x):
    """SPICE number -> float"""
    if isinstance(x, (int, float)):
        return float(x)
    s = str(x).lower().replace("meg", "e6")
    mult = {"p": 1e-12, "n": 1e-9, "u": 1e-6, "m": 1e-3, "k": 1e3}
    return float(s[:-1]) * mult[s[-1]] if s[-1] in mult else float(s)


def switches(cfg):
    """write tubes: (name, write node, cathodes on that node)"""
    if cfg == "full":
        return [(f"s{k}", f"b{k}", [k]) for k in range(10)]
    if cfg == "r0":
        return [("s0", "b0", [0]), ("sc", "bc", list(range(1, 10)))]
    if cfg == "r09":
        return [("s0", "b0", [0]), ("s9", "b9", [9]), ("sc", "bc", list(range(1, 9)))]
    raise ValueError(cfg)


def bnode(cfg, k):
    for _, b, ks in switches(cfg):
        if k in ks:
            return b


class Stim:
    def __init__(self, p):
        self.p = p
        self.ev = {}

    def pulse(self, node, t0, t1):
        self.ev.setdefault(node, []).append((t0, t1))

    def pwl(self, node, idle, active, tr=20e-9):
        pts = [(0.0, idle)]
        for t0, t1 in sorted(self.ev.get(node, [])):
            pts += [(t0, idle), (t0 + tr, active), (t1, active), (t1 + tr, idle)]
        return "PWL(" + " ".join(f"{t:.5e} {v}" for t, v in pts) + ")"

    def op(self, op, t):
        p = self.p
        a0 = t + p["PD"]
        pw, gap = p["PW"], -p["OV"]
        if op == "inc":
            self.pulse("ha", a0, a0 + pw)
            self.pulse("hb", a0 + pw + gap, a0 + 2 * pw + gap)
        elif op == "dec":
            self.pulse("hb", a0, a0 + pw)
            self.pulse("ha", a0 + pw + gap, a0 + 2 * pw + gap)
        elif op == "A":
            self.pulse("ha", a0, a0 + pw)
        elif op == "B":
            self.pulse("hb", a0, a0 + pw)
        elif op.startswith("w"):
            d = int(op[1:])
            sw = switches(p["CFG"])
            if not any(d in ks and len(ks) == 1 for _, _, ks in sw):
                raise ValueError(f"CFG {p['CFG']} cannot write {d}")
            # the write starts at the Clk edge (accept cycle), not after the phase delay
            for name, _, ks in sw:
                if d not in ks:
                    self.pulse(f"w{name}", t + 0.2e-6, t + 0.2e-6 + p["WRW"])
            self.pulse("lift", t + 0.2e-6, t + 0.2e-6 + p["WRW"])
        elif op != "nop":
            raise ValueError(op)


def netlist(st, stop, p, out_vecs, dat):
    cfg = p["CFG"]
    sw = switches(cfg)
    L = ["* dekatron module", f".include {LIBS}/A110.sub", f".include {LIBS}/6N16B.sub",
         f".include {LIBS}/6Zh2B.sub", f".include {LIBS}/6Kh7B.sub",
         f"VE e 0 PWL(0 0 {T0 / 3:.3e} {p['E']})", f"RA e a {p['RA']}", f"CW a 0 {p['CW']}",
         "V150 v150 0 150", "VN50 vn50 0 -50", f"VP vp 0 {p['VP']}", f"VEK nek 0 {-val(p['EK'])}",
         f"VPU vpu 0 {p['VPU']}", f"VKEY vkey 0 {st.pwl('lift', p['VKEY'], p['VKW']) if p['VKW'] != '' else p['VKEY']}",
         f"XT a {' '.join(f'k{k}' for k in range(10))} g1 g2 A110"]
    # read lines: wiring capacitance, Rk to the write node, gate grids
    halves = []
    for k in range(10):
        if p["READ"] == "mid":        # Rk split: K -> RK1 -> midpoint (gate grids) -> RK2 -> B
            L += [f"CL{k} k{k} 0 {p['CL']}", f"RK{k} k{k} rd{k} {p['RK1']}",
                  f"RK2{k} rd{k} {bnode(cfg, k)} {p['RK2']}"]
            for j in range(int(p["NLOAD"])):
                halves.append((f"pl{k}_{j}", f"rd{k}", "0"))
                L.append(f"RL{k}_{j} v150 pl{k}_{j} 10k")
            continue
        L += [f"CL{k} k{k} 0 {p['CL']}", f"RK{k} k{k} {bnode(cfg, k)} {p['RK']}"]
        if p["READ"] == "cath":       # read at the write tube cathode (below)
            continue
        if p["READ"] == "diode":      # gate grid pulled to ground, vacuum diode to the line
            L += [f"RPU{k} rd{k} vpu {p['RPU']}", f"XDR{k} rd{k} k{k} 6Kh7B", f"CDR{k} rd{k} 0 {p['CDR']}",
                  ] + ([f"CDS{k} rd{k} k{k} {p['CDS']}"] if val(p["CDS"]) > 0 else [])
            for j in range(int(p["NLOAD"])):
                halves.append((f"pl{k}_{j}", f"rd{k}", "0"))
                L.append(f"RL{k}_{j} v150 pl{k}_{j} 10k")
            continue
        if p["READ"] == "div":        # line -> R1 || C1 -> gate grids, R2 to ground
            L += [f"RD1{k} k{k} rd{k} {p['RD1']}", f"CD1{k} k{k} rd{k} {p['CD1']}",
                  f"RD2{k} rd{k} 0 {p['RD2']}"]
            gnode = f"rd{k}"
        else:                         # grids straight on the line
            gnode = f"k{k}"
        for j in range(int(p["NLOAD"])):
            halves.append((f"pl{k}_{j}", gnode, "0"))
            L.append(f"RL{k}_{j} v150 pl{k}_{j} 10k")
    # write tubes: plate on the write node, grid via Cc from the driver, Rc to the cathode
    for name, b, _ in sw:
        L += [f"CB{name} {b} 0 {p['CB']}", f"RP{name} vp {b} {p['RP']}", f"VW{name} wd{name} 0 {st.pwl('w' + name, 150, 50)}",
              f"RW{name} wd{name} w{name} {p['RW']}", f"CC{name} w{name} gs{name} {p['CC']}"]
        if p["READ"] == "cath":       # tube cathode = read node: Rs to -EK, grid returned to it
            L += [f"RS{name} c{name} nek {p['RS']}", f"RC{name} gs{name} c{name} {p['RC']}",
                  f"CLC{name} c{name} 0 {p['CL']}"]
            halves.append((b, f"gs{name}", f"c{name}"))
            for j in range(int(p["NLOAD"])):
                halves.append((f"plc{name}_{j}", f"c{name}", "0"))
                L.append(f"RLC{name}_{j} v150 plc{name}_{j} 10k")
        else:
            L.append(f"RC{name} gs{name} nek {p['RC']}")
            halves.append((b, f"gs{name}", "nek"))
    if len(halves) % 2:
        halves.append(("nek", "nek", "nek"))
    for i in range(0, len(halves), 2):
        (pa, ga, ka), (pb, gb, kb) = halves[i], halves[i + 1]
        L.append(f"XN{i // 2} {pa} {ga} {ka} {pb} {gb} {kb} 6N16B")
    # guide keys and bias (Yablonsky fig. 3-1, 3-4, 4-8)
    L += [f"VSM usm0 0 {p['USM']}", "RSMD usm0 usm 10k", "CSMD usm 0 1u"]
    en = 150 if int(p["EN"]) else 50
    for g, h in (("g1", "ha"), ("g2", "hb")):
        L += [f"VH{g} h{g} 0 {st.pwl(h, 50, 150)}",
              f"R1{g} h{g} l1{g} 470k", f"C1{g} h{g} l1{g} 2.7p", f"R2{g} l1{g} vn50 200k",
              f"VEN{g} en{g} 0 {en}", f"R3{g} en{g} l3{g} 470k", f"C3{g} en{g} l3{g} 6.8p",
              f"R4{g} l3{g} vn50 200k",
              f"XK{g} ka{g} l3{g} sg{g} 0 l1{g} 6Zh2B", f"RS{g} v150 sg{g} 15k",
              f"RKEY{g} vkey ka{g} {p['RKEY']}", f"CKA{g} ka{g} 0 {p['CKA']}", f"CP{g} ka{g} {g} {p['CP']}",
              f"RSM{g} {g} usm {p['RSM']}"]
        if int(p["DIODE"]):
            L.append(f"XD{g} {g} usm 6Kh7B")
    L += [".options method=gear reltol=1e-4 abstol=1e-12 vntol=1e-5 itl4=200",
          f".tran 10n {stop:.5e} 0 20n", ".control", "run", f"linearize {' '.join(out_vecs)}",
          f"wrdata {dat} {' '.join(out_vecs)}", ".endc", ".end"]
    return "\n".join(L) + "\n"


def simulate(p, ops):
    """run ops (one per slot after T0); returns dict of arrays: t, k0..k9, ik0..ik9, b*, g1, g2, a"""
    st = Stim(p)
    for n, op in enumerate(ops):
        st.op(op, T0 + n * p["SLOT"])
    stop = T0 + len(ops) * p["SLOT"]
    bn = [b for _, b, _ in switches(p["CFG"])]
    rd = [f"rd{k}" for k in range(10)] if p["READ"] in ("div", "mid", "diode") else []
    if p["READ"] == "cath":
        rd = [f"c{n}" for n, _, _ in switches(p["CFG"])]
    vecs = ([f"v(k{k})" for k in range(10)] + [f"v({b})" for b in bn] + ["v(g1)", "v(g2)", "v(a)", "v(kag1)"]
            + [f"v({n})" for n in rd])
    names = [f"k{k}" for k in range(10)] + bn + ["g1", "g2", "a", "ka"] + rd
    dat = tempfile.NamedTemporaryFile(suffix=".dat", delete=False).name
    with tempfile.NamedTemporaryFile("w", suffix=".cir", delete=False) as f:
        f.write(netlist(st, stop, p, vecs, dat))
        fn = f.name
    try:
        o = subprocess.run([sys.executable, NGRUN, fn], capture_output=True, text=True, timeout=3600)
        d = np.loadtxt(dat)
    except Exception:
        print(o.stdout[-3000:] if 'o' in dir() else "", o.stderr[-2000:] if 'o' in dir() else "")
        raise
    finally:
        os.unlink(fn)
        if os.path.exists(dat):
            os.unlink(dat)
    r = {"t": d[:, 0]}
    for i, n in enumerate(names):
        r[n] = d[:, 2 * i + 1]
    rk = val(p["RK"]) if p["READ"] != "mid" else val(p["RK1"]) + val(p["RK2"])
    for k in range(10):
        r[f"ik{k}"] = (r[f"k{k}"] - r[bnode(p["CFG"], k)]) / rk * 1e3
        if p["READ"] == "grid":
            r[f"rd{k}"] = r[f"k{k}"]      # the gate grid sees the line itself
        elif p["READ"] == "cath":
            r[f"rd{k}"] = r["c" + [n for n, _, ks in switches(p["CFG"]) if k in ks][0]]
    return r


def at(r, name, t):
    return float(np.interp(t, r["t"], r[name]))


def rtl_model(ops, start):
    d, out = start, []
    for op in ops:
        if op == "inc":
            d = (d + 1) % 10
        elif op == "dec":
            d = (d - 1) % 10
        elif op.startswith("w"):
            d = int(op[1:])
        out.append(d)
    return out


def slot_check(r, p, ops):
    """per slot: lit cathodes (Ik > 0.3 mA) and read lines at the next Clk edge (end of slot)"""
    rows = []
    t_pu = T0 - 0.1e-6
    lit0 = [k for k in range(10) if at(r, f"ik{k}", t_pu) > 0.3]
    exp = rtl_model(ops, lit0[0] if lit0 else 0)
    for n, (op, e) in enumerate(zip(ops, exp)):
        te = T0 + (n + 1) * p["SLOT"] - 20e-9
        lit = [k for k in range(10) if at(r, f"ik{k}", te) > 0.3]
        lv = [at(r, f"rd{k}", te) for k in range(10)]   # what the gate grid sees
        read = ["1" if v > VSW else ("0" if v < VIL else "X") for v in lv]
        grp = {k: [n for n, _, ks in switches(p["CFG"]) if k in ks][0] for k in range(10)}
        want = ["1" if (grp[k] == grp[e] if p["READ"] == "cath" else k == e) else "0" for k in range(10)]
        ok = lit == [e] and read == want
        rows.append(dict(op=op, lit=lit, exp=e, ok=ok, read="".join(read),
                         hi=lv[e], lo=max([v for k, v in enumerate(lv) if want[k] == "0"] or [-99])))
    return lit0, rows


SEQ = {"full": ["w0", "inc", "inc", "inc", "dec", "A", "B", "nop", "w7", "inc", "inc", "inc", "dec", "dec",
                "w5", "w4", "w9", "inc", "w1", "dec", "dec"],
       "r0": ["w0", "inc", "inc", "dec", "A", "B", "w0", "dec", "dec", "w0", "inc"],
       "r09": ["w0", "inc", "w9", "inc", "dec", "dec", "w0", "dec", "w9", "w0"],
       "writes": ["w0", "nop", "w5", "nop", "w4", "nop", "w9", "nop", "w1", "nop", "nop"],
       "steps": ["w0", "inc", "inc", "inc", "dec", "A", "B", "nop", "dec", "dec", "inc"]}


def seq(p, quiet=False):
    ops = SEQ[p.get("SEQ", p["CFG"])]
    r = simulate(p, ops)
    lit0, rows = slot_check(r, p, ops)
    bad = sum(not x["ok"] for x in rows)
    if not quiet:
        print(f"CFG {p['CFG']}: power-up lit {lit0}")
        for x in rows:
            print(f"{x['op']:4} -> lit {x['lit']}  RTL {x['exp']}  read {x['read']}  "
                  f"grid lit {x['hi']:6.2f} V  grid other max {x['lo']:6.2f} V  {'ok' if x['ok'] else 'MISMATCH'}")
        print(f"{len(rows) - bad}/{len(rows)} slots match the RTL model and read correctly")
    return bad, rows, r


def levels(p):
    ops = ["w0", "nop", "inc", "nop"]
    r = simulate(p, ops)
    S = p["SLOT"]
    te = T0 + 2 * S - 0.5e-6            # K0 lit, quiet
    b0, b1 = bnode(p["CFG"], 0), bnode(p["CFG"], 1)
    print(f"CFG {p['CFG']}  RK {p['RK']}  RP {p['RP']} to {p['VP']} V  -EK {-val(p['EK'])} V  NLOAD {p['NLOAD']}")
    print(f"lit {[k for k in range(10) if at(r, f'ik{k}', te) > 0.3]}")
    print(f"K0 lit: Ik {at(r, 'ik0', te):.3f} mA, K0 {at(r, 'k0', te):6.2f} V, B0 {at(r, b0, te):6.2f} V, "
          f"gate grid {at(r, 'rd0', te):6.2f} V")
    print(f"K1 unlit: K1 {at(r, 'k1', te):6.2f} V, B1 {at(r, b1, te):6.2f} V, gate grid {at(r, 'rd1', te):6.2f} V")
    print(f"anode {at(r, 'a', te):.1f} V, guides g1 {at(r, 'g1', te):.2f} V g2 {at(r, 'g2', te):.2f} V")
    ib = (val(p["VP"]) - at(r, b1, te)) / val(p["RP"]) * 1e3
    print(f"Rp current {ib:.2f} mA per tube, Rp power {(val(p['VP']) - at(r, b1, te)) * ib:.0f} mW")
    # write: closed nodes
    tw = T0 + 0.2e-6 + val(p["WRW"]) - 0.2e-6
    print(f"during w0: K5 {at(r, 'k5', tw):6.1f} V (closed), K0 {at(r, 'k0', tw):6.1f} V (target)")
    # guide pulse (slot 3, inc)
    t3 = T0 + 2 * S
    w = (r["t"] > t3) & (r["t"] < t3 + S)
    print(f"guide g1 during inc: min {r['g1'][w].min():.1f} V, key plate min {r['ka'][w].min():.1f} V")
    # read edges after the step: new K1 crosses VSW, old K0 below VIL
    tb = t3 + p["PD"] + 2 * p["PW"] - p["OV"]
    w = (r["t"] > tb)
    t_new = r["t"][w][np.argmax(r["rd1"][w] > VSW)] - tb
    t_old = r["t"][w][np.argmax(r["rd0"][w] < VIL)] - tb
    print(f"after phase B ends: K1 reads 1 after {t_new * 1e6:.2f} us, K0 reads 0 after {t_old * 1e6:.2f} us; "
          f"slot ends {(t3 + S - tb) * 1e6:.2f} us after phase B")


def count(p, n=30, quiet=False):
    ops = ["w0"] + ["inc"] * n + ["nop"] * 3
    r = simulate(p, ops)
    lit0, rows = slot_check(r, p, ops)
    bad = sum(not x["ok"] for x in rows)
    S = p["SLOT"]
    g_idle0 = at(r, "g1", T0 + S + 0.5e-6)
    g_last = at(r, "g1", T0 + n * S + 0.5e-6)
    if not quiet:
        print(f"{n} x +1 at {1e-3 / S:.0f} kHz: {len(rows) - bad}/{len(rows)} slots ok, final lit {rows[-1]['lit']}")
        print(f"guide 1 bias before the run {g_idle0:.2f} V, before the last step {g_last:.2f} V "
              f"(drift {g_last - g_idle0:+.2f} V)")
    return bad, g_last - g_idle0


def _job(a):
    name, v, p = a
    q = dict(p)
    q[name] = v
    try:
        if q.get("TEST") == "count":
            bad, drift = count(q, 30, quiet=True)
            return v, bad, f"drift {drift:+.2f} V"
        bad, rows, _ = seq(q, quiet=True)
        his = min(x["hi"] for x in rows)
        los = max(x["lo"] for x in rows)
        badops = ",".join(f"{i}:{x['op']}" for i, x in enumerate(rows) if not x["ok"])
        return v, bad, f"grid lit min {his:6.2f} V  grid other max {los:6.2f} V  {badops}"
    except Exception as e:
        return v, -1, f"failed: {e}"


def sweep(p, name, values):
    with Pool(min(len(values), os.cpu_count() or 1)) as pool:
        res = pool.map(_job, [(name, v, p) for v in values])
    print(f"{name:>8}  result")
    for v, bad, info in res:
        print(f"{v:>8}  {'ok ' if bad == 0 else ('ERR' if bad < 0 else f'{bad} bad')}  {info}")


def _wjob(a):
    w, start, target, p = a
    q = dict(p)
    q["WRW"] = w
    ops = [f"w{start}", f"w{target}", "nop"]
    r = simulate(q, ops)
    S = q["SLOT"]
    te = T0 + 2 * S - 20e-9
    lit = [k for k in range(10) if at(r, f"ik{k}", te) > 0.3]
    t1 = T0 + S + 0.2e-6
    w_ = r["t"] > t1
    t_on = r["t"][w_][np.argmax(r[f"ik{target}"][w_] > 0.3)] - t1
    return w, start, target, lit, t_on


def wtime(p):
    widths = [0.5e-6, 1e-6, 1.5e-6, 2e-6, 3e-6, 5e-6]
    jobs = [(w, s, t, p) for w in widths for (s, t) in ((0, 1), (0, 5), (3, 8))]
    with Pool(min(len(jobs), os.cpu_count() or 1)) as pool:
        res = pool.map(_wjob, jobs)
    print(f"{'W width':>8}  from -> to  lit at slot end  target current > 0.3 mA after")
    for w, s, t, lit, t_on in res:
        print(f"{w * 1e6:6.1f} us  {s} -> {t}   {str(lit):8}  {t_on * 1e6:5.2f} us  {'ok' if lit == [t] else '--'}")


def plot(p, fn):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    ops = ["w3", "w7", "inc", "dec"]
    r = simulate(p, ops)
    S = p["SLOT"]
    t = (r["t"] - T0) * 1e6
    sel = t > -2
    fig, ax = plt.subplots(4, 1, figsize=(11, 9), sharex=True, gridspec_kw={"height_ratios": [1, 1.4, 1.4, 1.2]})
    ax[0].plot(t[sel], r["a"][sel], label="anode")
    ax[0].set_ylabel("V")
    for k in (3, 7, 8):
        ax[1].plot(t[sel], r[f"k{k}"][sel], label=f"K{k} (read line)")
    ax[1].axhline(VIL, ls=":", c="gray")
    ax[1].axhline(VSW, ls="--", c="gray")
    ax[1].set_ylim(-30, 160)
    ax[1].set_ylabel("V")
    for k in (3, 7, 8):
        ax[2].plot(t[sel], r[f"ik{k}"][sel], label=f"I K{k}")
    ax[2].set_ylabel("mA")
    ax[3].plot(t[sel], r["g1"][sel], label="guide ring 1")
    ax[3].plot(t[sel], r["g2"][sel], label="guide ring 2")
    ax[3].set_ylabel("V")
    ax[3].set_xlabel("t, us (slots of 10 us: write 3, write 7, +1, -1)")
    for a in ax:
        a.grid(alpha=0.3)
        a.legend(loc="upper right", fontsize=8)
        for n in range(len(ops) + 1):
            a.axvline(n * S * 1e6, c="k", lw=0.5)
    fig.suptitle(f"Dekatron module, CFG {p['CFG']}: RK {p['RK']}, RP {p['RP']} to {p['VP']} V, "
                 f"-EK {-val(p['EK'])} V, Usm {p['USM']} V, RKEY {p['RKEY']}")
    fig.tight_layout()
    fig.savefig(fn, dpi=100)
    print(fn)


def parse(args):
    p = dict(DEF)
    for a in args:
        if "=" in a:
            k, v = a.split("=", 1)
            p[k] = v if k in ("CFG", "TEST", "READ", "SEQ") or not v.replace(".", "").replace("-", "").replace("e", "").isdigit() else float(v)
    for k in ("PW", "OV", "WRW", "SLOT", "PD"):
        p[k] = val(p[k])
    return p, [a for a in args if "=" not in a]


if __name__ == "__main__":
    p, w = parse(sys.argv[1:])
    cmd = w[0] if w else "seq"
    if cmd == "seq":
        sys.exit(1 if seq(p)[0] else 0)
    elif cmd == "levels":
        levels(p)
    elif cmd == "count":
        count(p, int(w[1]) if len(w) > 1 else 30)
    elif cmd == "sweep":
        sweep(p, w[1], w[2:])
    elif cmd == "wtime":
        wtime(p)
    elif cmd == "plot":
        plot(p, w[1] if len(w) > 1 else os.path.join(IMG, "dek_module_spice.png"))
