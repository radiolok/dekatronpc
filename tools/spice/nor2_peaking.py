#!/usr/bin/env python3
"""NOR2_N16 anode peaking check (sch/logic/NOR2_N16/README.md, doc/bonch_bruevich_lamps_review.md §8).
Same chain as nor2_sweep.py, but the inductor goes only where it is asked for:
L in series with Ra of the DUT, Lmap = {'da': ..., 'db': ...} for the two driver gates, Rd damping across L.
Book rule (Bonch-Bruevich p. 166): La = p * Ra^2 * C, p = 0.35.
usage: nor2_peaking.py [cases.py]; a cases file defines JOBS = [(name, params, grids), ...]"""
import os, re, sys, subprocess, tempfile
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nor2_sweep as N


def nor(t, a, b, p):
    L = p.get('Lmap', {}).get(t, p.get('L') if t == 'd' else None)
    s = f"X{t} p{t} {a} 0 p{t} {b} 0 6N16B\n"
    if not L:
        return s + f"RA{t} vcc p{t} {p['Ra']}\n"
    s += f"RA{t} vcc pl{t} {p['Ra']}\nLA{t} pl{t} p{t} {L}\n"
    if p.get('Rd'): s += f"RD{t} pl{t} p{t} {p['Rd']}\n"
    return s


N.nor = nor
EXTRA = """meas tran pmax max v(pd) from=0.5u to=10u
meas tran pmin min v(pd) from=0.5u to=10u
meas tran r10 when v(pd)=50 rise=1 td=7.9u
meas tran r90 when v(pd)=136 rise=1 td=7.9u
meas tran icc avg i(VCC) from=0 to=10u
"""


def run(arg):
    name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"nor2_peaking_{os.getpid()}.cir")
    open(fn, "w").write(N.deck(p, n).replace("meas tran icc avg i(VCC) from=0 to=10u\n", EXTRA))
    o = subprocess.run(["python3", N.NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def fmt(name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    return (f"{name:24s} grids={n:2d} | VOH={g('voh'):5.1f} VOL={g('vol1'):4.1f}/{g('vol2'):4.1f} plate {g('pmin'):5.1f}..{g('pmax'):5.1f}"
            f" | LV out {g('yll'):5.1f}/{g('ylh'):5.2f} min {g('ymin'):5.1f} grid {g('gmin'):5.1f}"
            f" | tpHL={g('tphl',1e9):4.0f} tpLH={g('tplh',1e9):4.0f} plate 10-90 {1e9*(g('r90')-g('r10')):4.0f}"
            f" LV->LV {g('lvd_hl',1e9):4.0f}/{g('lvd_lh',1e9):4.0f}ns")


if __name__ == "__main__":
    b = dict(R1="470k", R2="200k", C1g=3.9, Ra="10k")
    drv = {'da': '0.5m', 'db': '0.5m'}
    JOBS = []
    for n, L in ((2, "0.5m"), (6, "1.5m"), (10, "1.5m")):
        JOBS += [("no L", b, n), (f"L {L} DUT only", dict(b, L=L), n), (f"L {L}, drivers 0.5m", dict(b, L=L, Lmap=drv), n)]
    if len(sys.argv) > 1: exec(open(sys.argv[1]).read())
    with Pool(8) as pool:
        for r in pool.map(run, JOBS): print(fmt(*r))
