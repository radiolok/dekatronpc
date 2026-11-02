#!/usr/bin/env python3
"""RSLATCH_J2N16 timing constraints by bisection (sch/logic/RSLATCH_J2N16/README.md).

usage: latch_timing.py [grids ...]      (default 2 6 10)
  wmin   shortest E pulse (LV, measured at -5 V crossings) that sets the latch from Q = 0 with S held high;
  setup  shortest time S has to rise before E falls (S crossing -5 V to E crossing -5 V);
  hold   time S has to stay high after E falls (with R rising when S falls, as in a D latch; the E-on-g3 /
         S-on-g1 pentode needs S until E has cut it off).
Every case is a pass/fail transient: Q must end above 120 V (set) and QN below 80 V. The same drivers and loads as
latch_sweep.py; the input edges are placed on the ideal HV sources, the result is re-measured on the LV grids.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import latch_sweep as L


def src(t, pts, lv, p, c1):
    """driver as in latch_sweep.driver but with explicit (time_us, bit) breakpoints"""
    s = "PWL(0 {}".format(150 if not pts[0][1] else 50)
    for tt, b in pts[1:]:
        prev = 150 if not pts[pts.index((tt, b)) - 1][1] else 50
        s += f" {tt:.4f}u {prev} {tt+0.02:.4f}u {150 if not b else 50}"
    s += ")"
    return (f"VS{t} hs{t} 0 {s}\n" + L.div(f"s{t}", f"hs{t}", f"is{t}", p, p['C1g'])
            + f"XD{t} pd{t} is{t} 0 pdx{t} nb 0 6N16B\nRD{t} vcc pd{t} 10k\nRDX{t} vcc pdx{t} 10k\n"
            + L.div(f"d{t}", f"pd{t}", lv, p, c1))


def deck(p, ngrid, S, R, E, stop, meas):
    s = f"* RSLATCH timing\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    s += src("s", S, "s", p, L.c1_in(p, 's')) + src("r", R, "r", p, L.c1_in(p, 'r')) + src("e", E, "e", p, L.c1_in(p, 'e'))
    cell, lq, lqn = L.rslatch("x", "s", "r", "e", "q", "qn", p, ext=ngrid)
    s += cell + L.div("yq", "q", "yq", p, p['C1g'] * ngrid) + L.div("yn", "qn", "yn", p, p['C1g'] * ngrid)
    s += L.loads("yq", p, ngrid, "q") + L.loads("yn", p, ngrid, "n")
    s += f".tran 2n {stop}u\n.control\nrun\n{meas}\nmeas tran qe find v(q) at={stop-0.05}u\n"
    s += f"meas tran ne find v(qn) at={stop-0.05}u\n.endc\n.end\n"
    return s


def sim(p, n, S, R, E, stop, meas=""):
    fn = os.path.join(tempfile.gettempdir(), f"latch_timing_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n, S, R, E, stop, meas))
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def lv_dt(a, da, b, db, t0):
    """meas line: time from v(a) crossing -5 V (direction da) to v(b) crossing -5 V, both after t0 us"""
    return f"meas tran dt trig v({a}) val=-5 {da}=1 td={t0}u targ v({b}) val=-5 {db}=1 td={t0}u"


# every case: reset (R, E high) until 3 us, then the experiment; x is the parameter in us
def case_wmin(x):
    S = [(0, 0), (3.5, 1)]; R = [(0, 1), (3.0, 0)]; E = [(0, 1), (3.0, 0), (5.0, 1), (5.0 + x, 0)]
    return S, R, E, 9.0, lv_dt("e", "rise", "e", "fall", 4.5)


def case_setup(x):
    S = [(0, 0), (6.0 - x, 1)]; R = [(0, 1), (3.0, 0)]; E = [(0, 1), (3.0, 0), (4.0, 1), (6.0, 0)]
    return S, R, E, 10.0, lv_dt("s", "rise", "e", "fall", 3.5)


def case_hold(x):
    # S high and E high from 4 us; E falls at 6 us; S falls and R rises x after that (D latch: D -> 0)
    S = [(0, 0), (4.0, 1), (6.0 + x, 0)]; R = [(0, 1), (3.0, 0), (6.0 + x, 1)]; E = [(0, 1), (3.0, 0), (4.0, 1), (6.0, 0)]
    return S, R, E, 10.0, lv_dt("e", "fall", "s", "fall", 5.5)


def ok(m):
    return m.get("qe", 0) > 120 and m.get("ne", 200) < 80


def bisect(arg):
    name, p, n = arg
    f = dict(wmin=case_wmin, setup=case_setup, hold=case_hold)[name]
    # pass for large x (wmin, setup) or for large x (hold: S kept longer); find the smallest passing x
    lo, hi = (-0.6, 2.0) if name == "hold" else (0.0, 2.0)
    if not ok(sim(p, n, *f(hi))): return name, n, float('nan'), float('nan')
    if ok(sim(p, n, *f(lo))): return name, n, lo, sim(p, n, *f(lo)).get("dt", float('nan')) * 1e9
    while hi - lo > 0.005:
        mid = (lo + hi) / 2
        if ok(sim(p, n, *f(mid))): hi = mid
        else: lo = mid
    m = sim(p, n, *f(hi))
    return name, n, hi, m.get("dt", float('nan')) * 1e9


if __name__ == "__main__":
    P = dict(L.BASE, **L.CHOSEN)
    grids = [int(x) for x in sys.argv[1:]] or [2, 6, 10]
    jobs = [(nm, P, n) for nm in ("wmin", "setup", "hold") for n in grids]
    with Pool(8) as pool:
        for nm, n, x, dt in pool.map(bisect, jobs):
            print(f"{nm:6s} N={n:2d}: source offset {x*1e3:5.0f} ns, on the LV grids {dt:5.0f} ns")
