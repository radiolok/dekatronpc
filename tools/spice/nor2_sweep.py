#!/usr/bin/env python3
"""NOR2_N16 transient sweep over fanout (sch/logic/NOR2_N16/README.md).
Gate: LV grid inputs (1 = +10, 0 = -20 V), HV plate output (1 = +150, 0 = +50 V); HV->LV divider R1 || C1 / R2 to -50 V.
Chain: ideal HV pulse -> divider -> driver NOR (inputs tied) -> divider -> DUT A/B;
DUT Y -> one divider (C1 = C1g x grids) -> N grids (N/2 load gates with both inputs tied).
Optional parameters: L (peaking inductor in series with Ra)."""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6N16B.sub")
def nor(t, a, b, p):
    s = f"X{t} p{t} {a} 0 p{t} {b} 0 6N16B\n"
    if p.get('L'): s += f"RA{t} vcc pl{t} {p['Ra']}\nLA{t} pl{t} p{t} {p['L']}\n"
    else: s += f"RA{t} vcc p{t} {p['Ra']}\n"
    return s
def div(t, hv, lv, p, ngrid):
    c1 = p['C1g'] * ngrid if p.get('scaleC', True) else p['C1g']
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {c1}p\nR2{t} {lv} nb {p['R2']}\n"
def pwl(bits, lo, hi):
    pts = []; t = 0
    for b in bits:
        v = hi if b else lo
        pts += [f"{t+20e-9:.3e} {v}", f"{t+2e-6:.3e} {v}"]; t += 2e-6
    return "PWL(0 %s %s)" % (lo, " ".join(pts))
def deck(p, ngrid):
    s = f"""* tran3
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
VSA sa 0 {pwl([1,0,1,0,1], 50, 150)}
VSB sb 0 {pwl([1,1,0,0,1], 50, 150)}
"""
    s += div('sa', 'sa', 'ia', p, 2) + div('sb', 'sb', 'ib', p, 2)
    s += nor('da', 'ia', 'ia', p) + div('da', 'pda', 'a', p, 1)
    s += nor('db', 'ib', 'ib', p) + div('db', 'pdb', 'b', p, 1)
    s += nor('d', 'a', 'b', p) + div('d', 'pd', 'yl', p, ngrid)
    for i in range(ngrid // 2): s += nor(f'l{i}', 'yl', 'yl', p)
    s += """.tran 5n 10u
.control
run
meas tran voh find v(pd) at=1.95u
meas tran vol1 find v(pd) at=3.95u
meas tran vol2 find v(pd) at=7.95u
meas tran lvh find v(a) at=3.95u
meas tran lvl find v(a) at=1.95u
meas tran ylh find v(yl) at=1.95u
meas tran yll find v(yl) at=3.95u
meas tran gmin min v(a) from=0.5u to=10u
meas tran ymin min v(yl) from=0.5u to=10u
meas tran tphl trig v(a) val=-5 rise=1 targ v(pd) val=100 fall=1
meas tran tplh trig v(a) val=-5 fall=1 td=7.9u targ v(pd) val=100 rise=1 td=7.9u
meas tran lvd_hl trig v(a) val=-5 rise=1 targ v(yl) val=-5 fall=1
meas tran lvd_lh trig v(a) val=-5 fall=1 td=7.9u targ v(yl) val=-5 rise=1 td=7.9u
meas tran icc avg i(VCC) from=0 to=10u
.endc
.end
"""
    return s
def run(arg):
    name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"nor2_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n))
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
def fmt(name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    return (f"{name:26s} grids={n:2d} | HV: VOH={g('voh'):5.1f} VOL1={g('vol1'):4.1f} VOL2={g('vol2'):4.1f} | LV in {g('lvl'):5.1f}/{g('lvh'):4.2f} out {g('yll'):5.1f}/{g('ylh'):4.2f} min {g('ymin'):5.1f} grid {g('gmin'):5.1f}"
            f" | tpHL={g('tphl',1e9):4.0f} tpLH={g('tplh',1e9):4.0f} LV->LV {g('lvd_hl',1e9):4.0f}/{g('lvd_lh',1e9):4.0f}ns")
if __name__ == "__main__":
    # usage: nor2_sweep.py [cases.py]; a cases file defines CASES = [(name, params), ...] and optionally GRIDS
    CASES = [("NOR2_N16", dict(R1="470k", R2="200k", C1g=3.9, Ra="10k"))]
    GRIDS = (2, 4, 6, 8, 10)
    if len(sys.argv) > 1: exec(open(sys.argv[1]).read())
    grids = GRIDS
    jobs = [(nm, p, n) for nm, p in CASES for n in grids]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
