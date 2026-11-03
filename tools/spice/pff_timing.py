#!/usr/bin/env python3
"""Pulse-clocked D flip-flop (pff_sweep.py, doc/tc_n5_pulse_dff.md) timing by bisection.

usage: pff_timing.py wmin|tcq|hold|setup [key=value ...] [grids ...]
  wmin : D steady, one rising clock edge; bisection on Rth (the g3 pulse time constant): the shortest pulse
         (g3 above -5 V) that flips the cell.
  tcq  : clock line crossing 100 V (rising) to Q / QN crossing 100 V, set and reset.
  hold : D = v at the edge and ~v `x` us after it: the smallest x for which the cell still takes v.
  setup: D = ~v until `x` us before the edge, then v: the smallest x for which the cell takes v.
  hold and setup run all four cases (state before the edge 0/1, value taken 0/1) and print each; the time is
  re-measured from the clock line crossing 100 V to the D pin crossing its threshold (100 V on the HV pin).
Every case: Q must end above 118 V and QN below 92 V (or the reverse). A deck that hangs (180 s) counts as a
failure and is reported.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import latch_sweep as L
import latch_timing as LT
import pff_sweep as PS
import dff_sweep as F


def deck(p, n, D, CK, stop, meas):
    s = f"* PFF timing\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    ct = [0.0] + [t for t, _ in CK[1:]]; cb = [CK[0][1]] + [b for _, b in CK[1:]]
    s += PS.clock(ct, cb, p)
    if p.get('dhv'):
        s += PS.drv_hv(F.wave([t for t, _ in D], [b for _, b in D]), "d", p)
        s += L.div("dl", "d", "dl", p, p['C1g'] * 2) + L.loads("dl", p, 2, "d")     # two more grids on the D net
    else:
        s += LT.src("d", D, "d", p, PS.c1d(p) + p['C1g'])
    s += PS.pff("x", "d", "ck", "q", "qn", p)
    s += L.div("yq", "q", "yq", p, p['C1g'] * n) + L.div("yn", "qn", "yn", p, p['C1g'] * n)
    s += L.loads("yq", p, n, "q") + L.loads("yn", p, n, "n")
    s += f".options method=gear\n.tran 2n {stop}u\n.control\nrun\n{meas}\nmeas tran qe find v(q) at={stop-0.05}u\n"
    s += f"meas tran ne find v(qn) at={stop-0.05}u\n.endc\n.end\n"
    return s


def sim(p, n, D, CK, stop, meas=""):
    fn = os.path.join(tempfile.gettempdir(), f"pff_timing_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n, D, CK, stop, meas))
    try:
        o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True, timeout=180).stdout
    except subprocess.TimeoutExpired:
        print(f"  ngspice hung: {fn} (counted as a failure)", file=sys.stderr)
        return {}
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


# every case: D low and a first clock edge at 1 us (resets the cell), the experiment edge at 6 us
E0, E1 = 1.0, 6.0
CK = [(0, 0), (E0, 1), (3.5, 0), (E1, 1), (9.0, 0)]


def DV(p): return 100 if p.get('dhv') else -5     # D threshold: HV middle or LV -5 V


def is_val(m, v):
    return (m.get('qe', 0) > 118 and m.get('ne', 200) < 92) if v else (m.get('qe', 200) < 92 and m.get('ne', 0) > 118)


def case(kind, x, p, init=0, v=1):
    """the cell holds `init` from the first edge; at the experiment edge it must take v.
    hold : D = v from 3 us, D = ~v at E1 + x;  setup: D = ~v from 3 us, D = v at E1 - x;
    wmin : D = v from 3 us, x = Rth in kohm"""
    if kind == "wmin":
        p = dict(p, Rth=x * 1e3)
        D = [(0, init), (3.0, v)]
        meas = (f"meas tran pw trig v(g3x) val=-5 rise=1 td={E1-0.2}u targ v(g3x) val=-5 fall=1 td={E1-0.2}u")
    elif kind == "hold":
        D = [(0, init), (3.0, v), (E1 + x, 1 - v)]
        meas = (f"meas tran dt trig v(ck) val=100 rise=1 td={E1-0.2}u targ v(d) val={DV(p)} {'fall' if v else 'rise'}=1 td={E1-0.2}u")
    else:
        D = [(0, init), (3.0, 1 - v), (E1 - x, v)]
        meas = (f"meas tran dt trig v(d) val={DV(p)} {'rise' if v else 'fall'}=1 td={E0+0.5}u targ v(ck) val=100 rise=1 td={E1-0.2}u")
    D = [D[0]] + [d for i, d in enumerate(D[1:], 1) if d[1] != D[i - 1][1]]    # drop non-changes
    return p, D, meas


def tcq(p, n):
    """clock (HV line 100 V, rising) to Q / QN crossing 100 V: set (D high) and reset (D low, from set)"""
    r = {}
    for nm, D, CKs in (("set", [(0, 0), (3.0, 1)], CK),
                       ("rst", [(0, 1), (3.0, 0)], CK)):
        qd, nd = ("rise", "fall") if nm == "set" else ("fall", "rise")
        meas = (f"meas tran q trig v(ck) val=100 rise=1 td={E1-0.2}u targ v(q) val=100 {qd}=1 td={E1-0.2}u\n"
                f"meas tran n trig v(ck) val=100 rise=1 td={E1-0.2}u targ v(qn) val=100 {nd}=1 td={E1-0.2}u")
        m = sim(p, n, D, CKs, 11.0, meas)
        r[nm] = (m.get('q', float('nan')) * 1e9, m.get('n', float('nan')) * 1e9)
    return r


def bisect(kind, p, n, lo, hi, init, v, it=8):
    """pass = the cell takes v; wmin: x = Rth in kohm, hold / setup: x in us; pass at hi"""
    def ok(x):
        pp, D, meas = case(kind, x, p, init, v)
        m = sim(pp, n, D, CK, 11.0, meas)
        return is_val(m, v), m
    a, b = lo, hi
    pa, _ = ok(a); pb, mb = ok(b)
    if pa == pb: return None, f"no bracket ({lo}: {pa}, {hi}: {pb})"
    for _ in range(it):
        c = (a + b) / 2; pc, mc = ok(c)
        if pc == pb: b, mb = c, mc
        else: a = c
    return b, mb


def run(arg):
    kind, p, n, init, v = arg
    if kind == "tcq": return kind, n, init, v, 0, tcq(p, n)
    rng = dict(wmin=(1.0, 60.0), hold=(-1.0, 1.5), setup=(-0.4, 3.0))[kind]
    x, m = bisect(kind, p, n, *rng, init, v)
    return kind, n, init, v, x, m


if __name__ == "__main__":
    args = sys.argv[1:]
    kind = args.pop(0)
    p = dict(PS.P)
    for a in [a for a in args if "=" in a]:
        k, v = a.split("=", 1); p[k] = float(v) if re.match(r"^-?[\d.]+(e-?\d+)?$", v) else v
    grids = [int(x) for x in args if "=" not in x] or [2, 6, 10]
    combos = [(0, 1)] if kind in ("wmin", "tcq") else [(0, 1), (1, 1), (0, 0), (1, 0)]
    with Pool(16) as pool:
        for kind_, n, init, v, x, m in pool.map(run, [(kind, p, n, i, v) for n in grids for i, v in combos]):
            if kind_ == "tcq":
                print(f"tcq   N={n:2d} set Q/QN {m['set'][0]:4.0f}/{m['set'][1]:4.0f} ns, reset Q/QN {m['rst'][0]:4.0f}/{m['rst'][1]:4.0f} ns")
            elif x is None:
                print(f"{kind_:5s} N={n:2d} {init}->{v} {m}")
            elif kind_ == "wmin":
                print(f"wmin  N={n:2d} Rth {x:5.1f}k  pulse {m.get('pw', float('nan'))*1e9:4.0f} ns")
            else:
                print(f"{kind_:5s} N={n:2d} {init}->{v} x {x*1e3:5.0f} ns at the source, {m.get('dt', float('nan'))*1e9:5.0f} ns on the pin")
