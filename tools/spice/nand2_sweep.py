#!/usr/bin/env python3
"""NAND2_J2 transient sweep over fanout (doc/nand2_j2_6zh2b.md).
Gate: one 6Zh2B, A on g1, B on g3 (LV: 1 = +10, 0 = -20 V), HV plate output (1 = +150, 0 = +50 V) through Ra,
screen through Rg2 from +150 V; HV->LV divider R1 || C1 / R2 to -50 V.
Chain: ideal HV pulse -> divider -> driver NAND (inputs tied) -> divider -> DUT A/B;
DUT Y -> one divider (C1 = C1g x grids) -> N grids (N/2 load gates with g1 and g3 tied).
States AB, 2 us each: 00 10 11 01 11 10 01 00 (B and A each switch the output both ways; 10 -> 01 is the hazard).
Divider C1 = C1g per g1 grid + C1g3 per g3 grid on the net (C1g3 defaults to C1g).
Optional parameters: C1g3, Cb (pF, g3 to -50 V inside the cell), Rk (cathode resistor),
M (extra instance parameters of the model, e.g. "MU2=16 CG3A=2.5P")."""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6Zh2B.sub")
SEQ_A = [0, 1, 1, 0, 1, 1, 0, 0]
SEQ_B = [0, 0, 1, 1, 1, 0, 1, 0]
# the KiCad testbench (two VPULSE sources): 00 10 11 01 01 11 10 00, every arc once, no hazard state
KICAD_A = [0, 1, 1, 0, 0, 1, 1, 0]
KICAD_B = [0, 0, 1, 1, 1, 1, 0, 0]
def nand(t, a, b, p):
    k = f"k{t}" if p.get('Rk') else "0"
    s = f"X{t} p{t} {b} s{t} {k} {a} 6Zh2B {p.get('M', '')}\nRA{t} vcc p{t} {p['Ra']}\nRS{t} vcc s{t} {p['Rg2']}\n"
    if p.get('Rk'): s += f"RK{t} k{t} 0 {p['Rk']}\n"
    if p.get('Cb'): s += f"CB{t} {b} nb {p['Cb']}p\n"
    return s
def div(t, hv, lv, p, n1, n3):
    """divider for an HV net that drives n1 g1-grids and n3 g3-grids"""
    c1 = p['C1g'] * n1 + p.get('C1g3', p['C1g']) * n3
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {c1}p\nR2{t} {lv} nb {p['R2']}\n"
def pwl(bits, lo, hi):
    pts = []; t = 0
    for b in bits:
        v = hi if b else lo
        pts += [f"{t+20e-9:.3e} {v}", f"{t+2e-6:.3e} {v}"]; t += 2e-6
    return "PWL(0 %s %s)" % ((hi if bits[0] else lo), " ".join(pts))
def edges(seq_a, seq_b):
    """(name, node, direction, time) of the first edge of each arc: tpHL_a = A rises with B high, etc."""
    out, seen = [], set()
    for i in range(1, len(seq_a)):
        for nm, s, o in (("a", seq_a, seq_b), ("b", seq_b, seq_a)):
            if s[i] != s[i - 1] and o[i] == o[i - 1] == 1:
                key = ("tphl_" if s[i] else "tplh_") + nm
                if key not in seen:
                    seen.add(key); out.append((key, nm, "rise" if s[i] else "fall", 2 * i))
    return out
def meas_lines(seq_a, seq_b, a, b, y, yl, stop):
    """.meas lines (without the leading dot): level at the end of each state, grid minima, hazard, delays."""
    L = [f"meas tran y{i} find v({y}) at={2*i+1.95}u" for i in range(len(seq_a))]
    L += [f"meas tran lvh find v({a}) at={2*seq_a.index(1)+1.95}u", f"meas tran lvl find v({a}) at=1.95u",
          f"meas tran ylh find v({yl}) at=1.95u"]
    i11 = next(i for i in range(len(seq_a)) if seq_a[i] and seq_b[i])
    L += [f"meas tran yll find v({yl}) at={2*i11+1.95}u"]
    L += [f"meas tran {n}min min v({x}) from=0.5u to={stop}u" for n, x in (("a", a), ("b", b), ("y", yl))]
    for i in range(1, len(seq_a)):
        if seq_a[i] != seq_a[i-1] and seq_b[i] != seq_b[i-1]:
            L.append(f"meas tran haz min v({y}) from={2*i}u to={2*i+2}u")
    for key, nm, d, t in edges(seq_a, seq_b):
        node = a if nm == "a" else b
        yd = "fall" if key.startswith("tphl") else "rise"
        L.append(f"meas tran {key} trig v({node}) val=-5 {d}=1 td={t-0.1:.1f}u targ v({y}) val=100 {yd}=1 td={t-0.1:.1f}u")
        if nm == "a":
            L.append(f"meas tran lv_{'hl' if yd == 'fall' else 'lh'} trig v({node}) val=-5 {d}=1 td={t-0.1:.1f}u targ v({yl}) val=-5 {yd}=1 td={t-0.1:.1f}u")
    return L
def meas_text(ngrid):
    stop = 2 * len(SEQ_A)
    return (f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(meas_lines(SEQ_A, SEQ_B, "a", "b", "pd", "yl", stop))
            + f"\nmeas tran vs11 find v(sd) at={2*next(i for i in range(len(SEQ_A)) if SEQ_A[i] and SEQ_B[i])+1.95}u"
            + "\n.endc\n.end\n")
def deck(p, ngrid):
    inv = lambda bits: [1 - x for x in bits]           # the driver gate inverts
    s = f"""* NAND2_J2 sweep
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
VSA sa 0 {pwl(inv(SEQ_A), 50, 150)}
VSB sb 0 {pwl(inv(SEQ_B), 50, 150)}
"""
    s += div('sa', 'sa', 'ia', p, 1, 1) + div('sb', 'sb', 'ib', p, 1, 1)
    s += nand('da', 'ia', 'ia', p) + div('da', 'pda', 'a', p, 1, 0)
    s += nand('db', 'ib', 'ib', p) + div('db', 'pdb', 'b', p, 0, 1)
    s += nand('d', 'a', 'b', p) + div('d', 'pd', 'yl', p, ngrid // 2, ngrid // 2)
    for i in range(ngrid // 2): s += nand(f'l{i}', 'yl', 'yl', p)
    s += meas_text(ngrid)
    return s
def run(arg):
    name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"nand2_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n))
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
def fmt(name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    ys = [g(f"y{i}") for i in range(len(SEQ_A))]
    hi = [y for y, a, b in zip(ys, SEQ_A, SEQ_B) if not (a and b)]
    lo = [y for y, a, b in zip(ys, SEQ_A, SEQ_B) if a and b]
    return (f"{name:24s} N={n:2d} | VOH {min(hi):5.1f} VOL {min(lo):4.1f}..{max(lo):4.1f} haz {g('haz'):5.1f}"
            f" | scr {g('vs11'):4.0f} | LV in {g('lvl'):5.1f}/{g('lvh'):4.2f} out {g('yll'):5.1f}/{g('ylh'):4.2f}"
            f" min a {g('amin'):5.1f} b {g('bmin'):5.1f} y {g('ymin'):5.1f}"
            f" | tpHL a/b {g('tphl_a',1e9):4.0f}/{g('tphl_b',1e9):4.0f} tpLH a/b {g('tplh_a',1e9):4.0f}/{g('tplh_b',1e9):4.0f}"
            f" LV->LV {g('lv_hl',1e9):4.0f}/{g('lv_lh',1e9):4.0f} ns")
if __name__ == "__main__":
    # usage: nand2_sweep.py [--kicad] [cases.py]; a cases file defines CASES = [(name, params), ...] and optionally GRIDS;
    # --kicad runs the input sequence of the KiCad testbench (fanout 10 there)
    CASES = [("NAND2_J2", dict(R1="470k", R2="200k", C1g=3.9, C1g3=6.8, Cb=15, Ra="15k", Rg2="15k"))]
    GRIDS = (2, 4, 6, 8, 10)
    args = sys.argv[1:]
    if "--kicad" in args:
        args.remove("--kicad"); SEQ_A, SEQ_B = KICAD_A, KICAD_B
    if args: exec(open(args[0]).read())
    jobs = [(nm, p, n) for nm, p in CASES for n in GRIDS]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
