#!/usr/bin/env python3
"""RSLATCH_J2N16 speed-up options (sch/logic/RSLATCH_J2N16/README.md, "Speed-up options").
Same bench as latch_sweep.py, with these extra parameters:
  pk = 'shunt': La in series with each Ra (anode peaking, as NOR2_N16);
       'series': Ls between the plate (Ra, tubes, in-cell feedback divider) and the output pin, Rs across Ls;
       'both': La and Ls.
  Ld, Ldr: choke in the 6N16B drivers' Ra and its damping resistor (NOR2_N16: 0.68 mH || 10k since 2026-11-01).
The 'worst' column is the slowest Q/QN arc of the sequence.
usage: latch_peaking.py [cases.py]; a cases file defines JOBS = [(name, params, grids), ...]"""
import os, re, sys
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import latch_sweep as L

orig_rs, orig_drv = L.rslatch, L.driver


def rslatch(t, s_, r_, e_, q, qn, p, ext=0):
    mode = p.get('pk')
    sfx = "i" if mode in ('series', 'both') else ""
    n, lq, lqn = orig_rs(t, s_, r_, e_, q + sfx, qn + sfx, p, ext)
    if sfx:
        n += f"LS{t}q {q}i {q} {p['Ls']}\nLS{t}n {qn}i {qn} {p['Ls']}\n"
        if p.get('Rs'): n += f"RSD{t}q {q}i {q} {p['Rs']}\nRSD{t}n {qn}i {qn} {p['Rs']}\n"
    if mode in ('shunt', 'both'):
        for node, tag in ((q + sfx, 'q'), (qn + sfx, 'n')):
            n = n.replace(f"RA{t}{tag} vcc {node} {p['Ra']}\n",
                          f"RA{t}{tag} vcc ra{t}{tag} {p['Ra']}\nLA{t}{tag} ra{t}{tag} {node} {p['La']}\n")
    return n, lq, lqn


def driver(t, bits, lv, p, c1):
    s = orig_drv(t, bits, lv, p, c1)
    if p.get('Ld'): s = s.replace(f"RD{t} vcc pd{t} 10k\n", f"RD{t} vcc pdl{t} 10k\nLD{t} pdl{t} pd{t} {p['Ld']}\n")
    if p.get('Ld') and p.get('Ldr'): s += f"RDD{t} pdl{t} pd{t} {p['Ldr']}\n"
    return s


L.rslatch, L.driver = rslatch, driver


def line(r):
    s = L.fmt(*r)
    ns = [int(x) for x in re.findall(r"(\d+)(?=/|\s|$)", s.split("Q/QN ns")[1])]
    return f"worst {max(ns) if ns else -1:4d} | " + s


if __name__ == "__main__":
    B = dict(L.BASE, **L.CHOSEN)
    D = dict(B, Ld="680u", Ldr="10k")
    JOBS = []
    for n in (2, 6, 10):
        JOBS += [("cell as drawn", B, n), ("drivers with La", D, n), ("drivers, undamped La", dict(B, Ld="680u"), n),
                 ("La 1m", dict(D, pk='shunt', La="1m"), n),
                 ("Rg2 12k", dict(D, Rg2="12k"), n),
                 ("La 1m + Rg2 12k", dict(D, pk='shunt', La="1m", Rg2="12k"), n),
                 ("La 1m + Ls 680u/22k + Rg2 12k", dict(D, pk='both', La="1m", Ls="680u", Rs="22k", Rg2="12k"), n),
                 ("feedback C1 5.6p", dict(D, C1f=5.6), n),
                 ("La 1m + Rg2 12k, C1 +10%", dict(D, pk='shunt', La="1m", Rg2="12k", C1p=2.97, C1f=4.29, C1g3=7.48, C1g=4.29), n),
                 ("La 1m + Rg2 12k, plain drivers", dict(B, pk='shunt', La="1m", Rg2="12k"), n)]
    if len(sys.argv) > 1: exec(open(sys.argv[1]).read())
    with Pool(8) as pool:
        for r in pool.map(L.run, JOBS): print(line(r))
