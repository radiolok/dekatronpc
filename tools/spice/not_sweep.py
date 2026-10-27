#!/usr/bin/env python3
"""NOT_N16 transient sweep over fanout (doc/not_n16_6n16b.md).
Cell: one 6N16B = two independent inverters, each triode with its own Ra to +150 V.
Gate: LV grid input (1 = +10, 0 = -20 V), HV plate output (1 = +150, 0 = +50 V); HV->LV divider R1 || C1 / R2 to -50 V.
Chain: ideal HV pulse -> divider -> driver NOT -> divider -> DUT grid; each DUT output -> one divider
(C1 = C1g x grids) -> N grids (N/2 load tubes, both halves on the net, each half with its own Ra).
States (A,B), 2 us each: 00 10 11 01 00. Every arc of A happens with B static and vice versa, so the
plate-to-plate capacitance (model CPP = datasheet Ca1a2, 0.5 pF) shows up as crosstalk on the quiet output.
Optional parameter: M (extra model parameters, e.g. "MU=20.8 CPP=0.65P")."""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6N16B.sub")
SEQ_A = [0, 1, 1, 0, 0]
SEQ_B = [0, 0, 1, 1, 0]
def tube(t, ga, gb, p):
    """one 6N16B: two inverters, plates p{t}a / p{t}b, each with its own Ra"""
    s = f"X{t} p{t}a {ga} 0 p{t}b {gb} 0 6N16B {p.get('M', '')}\nRA{t}a vcc p{t}a {p['Ra']}\nRA{t}b vcc p{t}b {p['Ra']}\n"
    return s
def div(t, hv, lv, p, ngrid):
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {p['C1g'] * ngrid}p\nR2{t} {lv} nb {p['R2']}\n"
def pwl(bits, lo, hi):
    pts = []; t = 0
    for b in bits:
        v = hi if b else lo
        pts += [f"{t+20e-9:.3e} {v}", f"{t+2e-6:.3e} {v}"]; t += 2e-6
    return "PWL(0 %s %s)" % ((hi if bits[0] else lo), " ".join(pts))
def meas_lines(a, b, ya, yb, yla, stop):
    """.meas lines (no leading dot), shared with the KiCad testbench: levels, grid minima, delays, crosstalk."""
    L = [f"meas tran ya{i} find v({ya}) at={2*i+1.95}u" for i in range(len(SEQ_A))]
    L += [f"meas tran yb{i} find v({yb}) at={2*i+1.95}u" for i in range(len(SEQ_A))]
    L += [f"meas tran lvh find v({a}) at=3.95u", f"meas tran lvl find v({a}) at=1.95u",
          f"meas tran ylh find v({yla}) at=1.95u", f"meas tran yll find v({yla}) at=3.95u"]
    L += [f"meas tran {n}min min v({x}) from=0.5u to={stop}u" for n, x in (("a", a), ("b", b), ("y", yla))]
    L += [f"meas tran tphl_a trig v({a}) val=-5 rise=1 td=1.9u targ v({ya}) val=100 fall=1 td=1.9u",
          f"meas tran tplh_a trig v({a}) val=-5 fall=1 td=5.9u targ v({ya}) val=100 rise=1 td=5.9u",
          f"meas tran tphl_b trig v({b}) val=-5 rise=1 td=3.9u targ v({yb}) val=100 fall=1 td=3.9u",
          f"meas tran tplh_b trig v({b}) val=-5 fall=1 td=7.9u targ v({yb}) val=100 rise=1 td=7.9u",
          f"meas tran lv_hl trig v({a}) val=-5 rise=1 td=1.9u targ v({yla}) val=-5 fall=1 td=1.9u",
          f"meas tran lv_lh trig v({a}) val=-5 fall=1 td=5.9u targ v({yla}) val=-5 rise=1 td=5.9u",
          # crosstalk on the static output: Y_A low while Y_B falls (4 us), Y_B low while Y_A rises (6 us),
          # Y_A high while Y_B rises (8 us)
          f"meas tran xlo_min min v({ya}) from=4u to=5u", f"meas tran xlo_max max v({yb}) from=6u to=7u",
          f"meas tran xhi_min min v({ya}) from=8u to=9u"]
    return L
def deck(p, ngrid):
    inv = lambda bits: [1 - x for x in bits]           # the driver inverts
    stop = 2 * len(SEQ_A)
    s = f"""* NOT_N16 sweep
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
VSA sa 0 {pwl(inv(SEQ_A), 50, 150)}
VSB sb 0 {pwl(inv(SEQ_B), 50, 150)}
"""
    s += div('sa', 'sa', 'ia', p, 1) + div('sb', 'sb', 'ib', p, 1)
    s += tube('d', 'ia', 'ib', p) + div('da', 'pda', 'a', p, 1) + div('db', 'pdb', 'b', p, 1)
    s += tube('x', 'a', 'b', p) + div('xa', 'pxa', 'yla', p, ngrid) + div('xb', 'pxb', 'ylb', p, ngrid)
    for i in range(ngrid // 2): s += tube(f'la{i}', 'yla', 'yla', p) + tube(f'lb{i}', 'ylb', 'ylb', p)
    s += f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(meas_lines("a", "b", "pxa", "pxb", "yla", stop))
    s += "\nmeas tran icc avg i(VCC) from=0 to=10u\n.endc\n.end\n"
    return s
def run(arg):
    name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"not_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n))
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
def fmt(name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    hi = [g(f"ya{i}") for i in range(5) if not SEQ_A[i]] + [g(f"yb{i}") for i in range(5) if not SEQ_B[i]]
    lo = [g(f"ya{i}") for i in range(5) if SEQ_A[i]] + [g(f"yb{i}") for i in range(5) if SEQ_B[i]]
    return (f"{name:20s} N={n:2d} | VOH {min(hi):5.1f}..{max(hi):5.1f} VOL {min(lo):4.1f}..{max(lo):4.1f}"
            f" | LV in {g('lvl'):5.1f}/{g('lvh'):4.2f} out {g('yll'):5.1f}/{g('ylh'):4.2f}"
            f" min a {g('amin'):5.1f} b {g('bmin'):5.1f} y {g('ymin'):5.1f}"
            f" | xtalk lo {g('xlo_min'):4.1f}..{g('xlo_max'):4.1f} hi {g('xhi_min'):5.1f}"
            f" | tpHL a/b {g('tphl_a',1e9):3.0f}/{g('tphl_b',1e9):3.0f} tpLH a/b {g('tplh_a',1e9):3.0f}/{g('tplh_b',1e9):3.0f}"
            f" LV->LV {g('lv_hl',1e9):3.0f}/{g('lv_lh',1e9):3.0f} ns")
if __name__ == "__main__":
    # usage: not_sweep.py [cases.py]; a cases file defines CASES = [(name, params), ...] and optionally GRIDS
    CASES = [("NOT_N16", dict(R1="470k", R2="200k", C1g=3.9, Ra="10k"))]
    GRIDS = (2, 4, 6, 8, 10)
    if len(sys.argv) > 1: exec(open(sys.argv[1]).read())
    jobs = [(nm, p, n) for nm, p in CASES for n in GRIDS]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
