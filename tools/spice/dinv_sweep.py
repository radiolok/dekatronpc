#!/usr/bin/env python3
"""Universal trigger board (doc/dinv_trigger_board.md): one RS core (RSLATCH_J2N16 topology) + half a 6N16B
inverter, wired as a D latch, a master-slave DFF (DFF_J2N16) or a pulse DFF (DFFP_J2N16), with the D input direct
or inverted.

Inverted D (dinv = 1): D goes straight to the R pentode g1 (the one on plate Q), the inverter output to the S pentode
g1 (plate QN), so Q takes ~D. Only the master latch of a DFF_J2N16 is swapped; the slave stays as drawn.
The reference of every check is inverted with it (a shift register with both stages inverted keeps the reference).

Extra parameters on top of latch_sweep / latch_peaking / dff_sweep / pff_sweep:
  dinv     1: inverted D
  pk, La   'shunt' + La: plate chokes in series with Ra in the RS core (latch_peaking.py)
  Li, Lir  choke (and its damping resistor) in the plate of the D / C inverter (NOR2_N16: 0.68 mH || 10k)

usage: dinv_sweep.py [table|timing]
  table : the functional checks of the doc (dlatch, dff, shift, pff single / shift) for each core, D and ~D
  timing: DFFP setup / hold of the inverted-D cell (pff_timing.py, four cases)
"""
import os, sys
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import latch_sweep as L
import latch_peaking            # noqa: F401  patches L.rslatch (pk / La) and L.driver (Ld / Ldr)
import dff_sweep as F
import pff_sweep as PS
import pff_timing as PT

_rs, _inv, _fdeck, _pdeck, _isval = L.rslatch, F.inv, F.deck, PS.deck, PT.is_val
DINV = [0]                      # pff_timing.is_val has no p: the flag of the current run


def rslatch(t, s_, r_, e_, q, qn, p, ext=0):
    if p.get('swap'): s_, r_ = r_, s_
    return _rs(t, s_, r_, e_, q, qn, p, ext)


def inv(t, a, plate, p, other=None):
    n = _inv(t, a, plate, p, other)
    if p.get('Li'):
        n = n.replace(f"RI{t}a vcc {plate} 10k\n", f"RI{t}a vcc ril{t} 10k\nLI{t} ril{t} {plate} {p['Li']}\n"
                      + (f"RIL{t} ril{t} {plate} {p['Lir']}\n" if p.get('Lir') else ""))
    return n


def dlatch(t, d, e, q, qn, p):
    n = F.inv(t, d, f"dn{t}", p) + L.div(f"{t}i", f"dn{t}", f"r{t}", p, p['C1p'])
    c, lq, lqn = L.rslatch(t, d, f"r{t}", e, q, qn, dict(p, swap=p.get('dinv')))
    return n + c, lq, lqn


def dff(t, d, c, q, qn, p):
    """dff_sweep.dff with the master swapped for dinv"""
    n = F.inv(t, d, f"dn{t}", p, other=(c, f"cn{t}"))
    n += L.div(f"{t}i", f"dn{t}", f"rm{t}", p, p['C1p'])
    n += L.div(f"{t}c", f"cn{t}", f"ec{t}", p, 2 * p['C1g3'])
    em, es = (f"ec{t}", c) if p['edge'] == "pos" else (c, f"ec{t}")
    cm, _, _ = L.rslatch(f"{t}m", d, f"rm{t}", em, f"qm{t}", f"qnm{t}", dict(p, swap=p.get('dinv')))
    n += L.div(f"{t}ms", f"qm{t}", f"ss{t}", p, p['C1p']) + L.div(f"{t}mr", f"qnm{t}", f"rs{t}", p, p['C1p'])
    cs, _, _ = L.rslatch(f"{t}s", f"ss{t}", f"rs{t}", es, q, qn, dict(p, swap=0))
    return n + cm + cs


_pff = PS.pff


def pff(t, d, ck, q, qn, p):
    return _pff(t, d, ck, q, qn, dict(p, swap=p.get('dinv')))


def fdeck(kind, p, ngrid, per, dly):
    s, ref = _fdeck(kind, p, ngrid, per, dly)
    return s, ([1 - b for b in ref] if p.get('dinv') and kind != "shift" else ref)


def pdeck(kind, p, ngrid, per, dly):
    s, ref = _pdeck(kind, p, ngrid, per, dly)
    return s, ([1 - b for b in ref] if p.get('dinv') and kind != "shift" else ref)


L.rslatch, F.inv, F.dlatch, F.dff, PS.pff, F.deck, PS.deck = rslatch, inv, dlatch, dff, pff, fdeck, pdeck
PT.is_val = lambda m, v: _isval(m, 1 - v if DINV[0] else v)

NOL = dict(La=None, Ld=None, Li=None, Rg2="15k")                  # the cells before TRS v0.58 (no chokes)
CORES = {"as drawn": NOL,                                         # Ra 10k, Rg2 15k, Cb 15 pF
         "La 1m+Rg2 12k": dict(NOL, La="1m", Rg2="12k"),          # the DFFP_J2N16 core values (TRS v0.58: all cells)
         "La 1m+Rg2 12k, Cb 0": dict(NOL, La="1m", Rg2="12k", Cb=0)}
INVL = dict(Li="680u", Lir="10k")


def fjob(arg):
    kind, name, p, n, per = arg
    r = F.run((kind, name, p, n, per, 0.25))
    return F.fmt(*r)


def pjob(arg):
    kind, name, p, n, per = arg
    r = PS.run((kind, name, p, n, per, 0.25))
    return PS.fmt(*r)


def table():
    FB = dict(L.BASE, **L.CHOSEN, edge="neg")
    jobs = []
    for cn, core in CORES.items():
        for li in (0, 1):
            for dv in (0, 1):
                p = dict(FB, **core, **(INVL if li else {}), dinv=dv)
                tag = f"{cn}{', inv La' if li else ''}{', ~D' if dv else ', D'}"
                for n in (2, 6, 10):
                    jobs += [("dlatch", tag, p, n, 4.0), ("dff", tag, p, n, 4.0), ("shift", tag, p, n, 4.0)]
                for n, per in ((2, 1.2), (6, 1.6), (10, 2.0)):
                    jobs.append(("shift", tag, p, n, per))
    pj = []
    for li in (0, 1):
        for dv in (0, 1):
            p = dict(PS.P, **(INVL if li else {}), dinv=dv)
            tag = f"DFFP{', inv La' if li else ''}{', ~D' if dv else ', D'}"
            for n in (2, 6):
                pj += [("single", tag, p, n, 4.0), ("shift", tag, p, n, 2.0), ("shift", tag, p, n, 1.2)]
    # the RSLATCH E network (Cb 15 pF on each g3) left on the DFFP core
    pj += [("single", "DFFP, Cb 15 on g3", dict(PS.P, Cb=30), n, 4.0) for n in (2, 6)]
    with Pool(16) as pool:
        for line in pool.map(fjob, jobs): print(line)
        for line in pool.map(pjob, pj): print(line)


def timing():
    DINV[0] = 1
    p = dict(PS.P, dinv=1)
    combos = [(0, 1), (1, 1), (0, 0), (1, 0)]
    with Pool(16) as pool:
        for kind in ("setup", "hold"):
            for kind_, n, init, v, x, m in pool.map(PT.run, [(kind, p, n, i, v) for n in (2, 6) for i, v in combos]):
                # D = v at the edge: the cell must take ~v (state init -> ~v is the stored value)
                tx = "no bracket" if x is None else f"{x*1e3:5.0f} ns at the source, {m.get('dt', float('nan'))*1e9:5.0f} ns on the pin"
                print(f"~D {kind_:5s} N={n:2d} D={v} (Q {1-init}->{1-v}) {tx}")


if __name__ == "__main__":
    {"table": table, "timing": timing}[(sys.argv[1:] or ["table"])[0]]()
