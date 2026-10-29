#!/usr/bin/env python3
"""DLATCH_J2N16 and DFF_J2N16 transient checks (sch/logic/RSLATCH_J2N16/README.md), built from the RSLATCH_J2N16 cell of
latch_sweep.py and one 6N16B (NOT_N16) for the inverters.

DLATCH: the RS latch with S = D and R = ~D; the inverter is half a 6N16B (Ra 10k) and its divider in the cell
(C1 = C1p, one pentode g1). The D pin loads one pentode g1 and one triode grid, E two g3 grids.
DFF (master-slave): master = DLATCH, slave = RS latch with S = Qm, R = QNm; one 6N16B inverts D and C.
  edge = "pos": master enable ~C, slave enable C: Q takes D at the rising edge of C (liberty DFF, clocked_on C).
  edge = "neg": master enable C, slave enable ~C (the owner's drawing): Q takes D at the falling edge.
Both latches are the same RSLATCH cell; the master outputs reach the slave S/R through their own dividers (C1p).

usage: dff_sweep.py dlatch|dff|shift [--period US] [--edge pos|neg] [--dly F] [--cskew PF] [grids ...]
  shift: two DFFs in a row on one clock, the first Q drives the second D (plus N-2 more grids): register to register.
  A sampled level passes only if it is valid for the next stage: "1" above 118 V, "0" below 92 V.
  Drivers and loads as in latch_sweep.py. D follows a fixed pattern and changes `dly` (fraction of the period)
  after the active edge, as it would from another flip-flop. The check samples Q just before every active edge
  and compares it with the reference.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import latch_sweep as L

PATTERN = [1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0]


def inv(t, a, plate, p, other=None):
    """one 6N16B: inverter a -> plate (Ra 10k); other = (grid, plate) for the second half or None (grid at -50 V)"""
    g2, p2 = other if other else ("nb", f"px{t}")
    return (f"XI{t} {plate} {a} 0 {p2} {g2} 0 6N16B {p.get('MN', '')}\nRI{t}a vcc {plate} 10k\nRI{t}b vcc {p2} 10k\n")


def dlatch(t, d, e, q, qn, p):
    n = inv(t, d, f"dn{t}", p) + L.div(f"{t}i", f"dn{t}", f"r{t}", p, p['C1p'])
    c, lq, lqn = L.rslatch(t, d, f"r{t}", e, q, qn, p)
    return n + c, lq, lqn


def dff(t, d, c, q, qn, p):
    """master-slave; returns the netlist"""
    n = inv(t, d, f"dn{t}", p, other=(c, f"cn{t}"))
    n += L.div(f"{t}i", f"dn{t}", f"rm{t}", p, p['C1p'])
    n += L.div(f"{t}c", f"cn{t}", f"ec{t}", p, 2 * p['C1g3'])
    if p.get('Cskew'): n += f"CSK{t} cn{t} 0 {p['Cskew']}p\n"     # extra inverter delay (race margin test)
    em, es = (f"ec{t}", c) if p['edge'] == "pos" else (c, f"ec{t}")
    cm, _, _ = L.rslatch(f"{t}m", d, f"rm{t}", em, f"qm{t}", f"qnm{t}", p)
    # the master outputs reach the slave inputs through their own dividers (one pentode g1 each), so both latches
    # are the same RSLATCH sheet
    n += L.div(f"{t}ms", f"qm{t}", f"ss{t}", p, p['C1p']) + L.div(f"{t}mr", f"qnm{t}", f"rs{t}", p, p['C1p'])
    cs, _, _ = L.rslatch(f"{t}s", f"ss{t}", f"rs{t}", es, q, qn, p)
    return n + cm + cs


def wave(times, bits, t0=0.0):
    pts = [f"0 {150 if not bits[0] else 50}"]
    for tt, b, pb in zip(times[1:], bits[1:], bits[:-1]):
        if b != pb: pts += [f"{tt:.4f}u {150 if not pb else 50}", f"{tt+0.02:.4f}u {150 if not b else 50}"]
    return "PWL(" + " ".join(pts) + ")"


def drv(t, times, bits, lv, p, c1):
    """ideal HV source (inverted bits) -> divider -> 6N16B triode -> divider c1 -> lv; as latch_sweep.driver"""
    return (f"VS{t} hs{t} 0 {wave(times, bits)}\n" + L.div(f"s{t}", f"hs{t}", f"is{t}", p, p['C1g'])
            + f"XD{t} pd{t} is{t} 0 pdx{t} nb 0 6N16B\nRD{t} vcc pd{t} 10k\nRDX{t} vcc pdx{t} 10k\n"
            + L.div(f"d{t}", f"pd{t}", lv, p, c1))


def stimulus(kind, per, dly, edge):
    """clock/enable and D breakpoints (us) and the reference Q sampled before each active edge"""
    n = len(PATTERN); half = per / 2
    # first 3 periods: initialise (D = 0), then the pattern
    bits = [0, 0, 0] + PATTERN
    ct, cb = [0.0], [0]
    for k in range(len(bits) + 1):
        ct += [k * per + half, (k + 1) * per]; cb += [1, 0]
    # active edge of the enable/clock: rising (pos / dlatch closes on the falling edge of E)
    act = [k * per + half for k in range(len(bits) + 1)] if (kind == "dff" and edge == "pos") else \
          [(k + 1) * per for k in range(len(bits) + 1)]
    dt, db = [0.0], [bits[0]]
    for k in range(1, len(bits)):
        dt.append(act[k] - per + dly * per); db.append(bits[k])
    # DFF: Q holds bits[k] from the k-th active edge to the next one, sample just before the next.
    # DLATCH: E closes at act[k] with D = bits[k]; sample half a period later, just before E opens again.
    samp = [act[k] + half - 0.03 if kind == "dlatch" else act[k + 1] - 0.03 for k in range(len(bits))]
    ref = list(bits)
    return ct, cb, dt, db, samp, ref, (len(bits) + 1) * per + half


def deck(kind, p, ngrid, per, dly):
    ct, cb, dt, db, samp, ref, stop = stimulus("dff" if kind == "shift" else kind, per, dly, p['edge'])
    if kind == "shift": ref = [0] + ref[:-1]          # one stage later
    s = f"* {kind} sweep\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    if kind == "dlatch":
        s += drv("c", ct, cb, "c", p, 2 * p['C1g3']) + drv("d", dt, db, "d", p, p['C1p'] + p['C1g'])
        cell, _, _ = dlatch("x", "d", "c", "q", "qn", p); s += cell
    elif kind == "dff":
        s += drv("c", ct, cb, "c", p, 2 * p['C1g3'] + p['C1g']) + drv("d", dt, db, "d", p, p['C1p'] + p['C1g'])
        s += dff("x", "d", "c", "q", "qn", p)
    else:   # shift: DFF y -> DFF x; the clock net drives both, y's Q drives x's D and N-2 more grids
        s += drv("c", ct, cb, "c", p, 2 * (2 * p['C1g3'] + p['C1g'])) + drv("d", dt, db, "d", p, p['C1p'] + p['C1g'])
        s += dff("y", "d", "c", "q1", "qn1", p)
        s += L.div("y1", "q1", "d1", p, p['C1p'] + p['C1g'] + p['C1g'] * max(ngrid - 2, 0))
        s += L.loads("d1", p, max(ngrid - 2, 0), "y") + L.div("y2", "qn1", "dn1", p, p['C1g'] * ngrid) + L.loads("dn1", p, ngrid, "z")
        s += dff("x", "d1", "c", "q", "qn", p)
    s += L.div("yq", "q", "yq", p, p['C1g'] * ngrid) + L.div("yn", "qn", "yn", p, p['C1g'] * ngrid)
    s += L.loads("yq", p, ngrid, "q") + L.loads("yn", p, ngrid, "n")
    m = [f"meas tran q{k} find v(q) at={t:.4f}u" for k, t in enumerate(samp)]
    m += [f"meas tran n{k} find v(qn) at={t:.4f}u" for k, t in enumerate(samp)]
    m += [f"meas tran {x}min min v({x}) from=0.5u to={stop}u" for x in ("c", "d", "yq")]
    for nd in ("rmx", "ecx", "rx", "fqxm", "fqnxm", "fqxs", "fqnxs", "fqx", "fqnx", "ssx", "rsx"):
        if f" {nd} " in s or f" {nd}\n" in s: m.append(f"meas tran m_{nd} min v({nd}) from=0.5u to={stop}u")
    # clock-to-Q of the first rising and falling Q transitions after the 4th period
    m += [f"meas tran tcq_r trig v(c) val=-5 {'rise' if (kind == 'dlatch' or p['edge'] == 'pos') else 'fall'}=1"
          f" td={3*per+0.1:.3f}u targ v(q) val=100 rise=1 td={3*per+0.1:.3f}u"]
    s += f".tran 5n {stop:.3f}u\n.control\nrun\n" + "\n".join(m) + "\n.endc\n.end\n"
    return s, ref


def run(arg):
    kind, name, p, n, per, dly = arg
    s, ref = deck(kind, p, n, per, dly)
    fn = os.path.join(tempfile.gettempdir(), f"dff_sweep_{os.getpid()}.cir")
    open(fn, "w").write(s)
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True).stdout
    m = {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
    return kind, name, n, per, m, ref


def fmt(kind, name, n, per, m, ref):
    q = [m.get(f"q{k}", float('nan')) for k in range(len(ref))]
    qn = [m.get(f"n{k}", float('nan')) for k in range(len(ref))]
    # a sampled level must be valid for the next stage: "1" above full-on (118 V), "0" below VIL (92 V)
    good = lambda v, b: v > 118 if b else v < 92
    err = sum(1 for k, r in enumerate(ref) if k >= 3 and not (good(q[k], r) and good(qn[k], not r)))
    hi = min([x for x, r in zip(q[3:], ref[3:]) if r] + [x for x, r in zip(qn[3:], ref[3:]) if not r])
    lo = max([x for x, r in zip(q[3:], ref[3:]) if not r] + [x for x, r in zip(qn[3:], ref[3:]) if r])
    grids = " ".join(f"{k[2:]} {v:5.1f}" for k, v in m.items() if k.startswith("m_"))
    return (f"{kind:6s} {name:14s} N={n:2d} T={per:5.2f}us {'OK ' if not err else f'ERR{err}'} | worst sampled hi {hi:5.1f} lo {lo:5.1f}"
            f" | min c {m.get('cmin', 0):5.1f} d {m.get('dmin', 0):5.1f} {grids} | tcq_r {m.get('tcq_r', float('nan'))*1e9:4.0f} ns")


if __name__ == "__main__":
    args = sys.argv[1:]
    kind = args.pop(0) if args and args[0] in ("dlatch", "dff", "shift") else "dff"
    per, edge, dly = 4.0, "pos", 0.25
    if "--period" in args: i = args.index("--period"); per = float(args[i + 1]); del args[i:i + 2]
    if "--edge" in args: i = args.index("--edge"); edge = args[i + 1]; del args[i:i + 2]
    if "--dly" in args: i = args.index("--dly"); dly = float(args[i + 1]); del args[i:i + 2]
    cskew = None
    if "--cskew" in args: i = args.index("--cskew"); cskew = float(args[i + 1]); del args[i:i + 2]
    grids = [int(x) for x in args] or [2, 6, 10]
    P = dict(L.BASE, **L.CHOSEN, edge=edge)
    if cskew: P['Cskew'] = cskew
    jobs = [(kind, edge, P, n, per, dly) for n in grids]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
