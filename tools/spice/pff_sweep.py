#!/usr/bin/env python3
"""Pulse-clocked D flip-flop (TC-N5, doc/tc_n5_pulse_dff.md): the Bonch-Bruevich bistable of RSLATCH_J2N16
(one 6N16B, cross-coupled) with two 6Zh2B steering gates, whose g3 get a short pulse differentiated from the
rising edge of the HV clock line. The bistable finishes the transition by regeneration after the pulse.

The chosen cell (dhv = 1, defaults in P):
    D is an HV pin. In the cell: D --150k--+--62k-- -50 V    -> S (g1 of the QN pentode), no C1: the delay that
                                          (g1 node ~5 pF)        keeps a new D off the gate until the pulse is over
                                 D --470k||3.9p--+--200k-- -50 V -> inverter grid (half a 6N16B, Ra 10k) -> plate DN
                                 DN --150k--+--62k-- -50 V    -> R (g1 of the Q pentode), no C1
    both g3 on node g3x:  CK (HV clock line) --Cc 3.9p-- g3x;  g3x --43k-- GND, g3x --130k-- -50 V (rest -12.4 V)
    plates: Ra 10k + La 1 mH to +150 V; screens Rg2 12k; feedback dividers as RSLATCH_J2N16 (470k || 3.9p / 200k).
The rising HV edge lifts g3x into its grid-current clamp; it decays back with tau = Rth (Cc + C_node), and the
pentode whose g1 is high pulls its plate down only while g3x is above about -5 V. The falling HV edge throws g3x
below the rest level by the same step (kept above -40 V). The clock line is an ideal HV source (50/150 V) with
rise/fall time tr and source resistance Rs.

Options kept for the record (doc/tc_n5_pulse_dff.md §3): dhv = 0 is the first attempt, an LV D pin as
DLATCH_J2N16 (optionally Rd / Cd in series with each g1); eg = 'g1' swaps the clock to g1 and D to g3; La = 0 drops
the chokes; R1s / R2s, C1a / C1c set the slow dividers.

usage: pff_sweep.py single|shift [--period US] [--dly F] [key=value ...] [grids ...]
  single: one cell, D from a driver changing `dly` periods after the active (rising) edge.
  shift : two cells in a row on one clock line, u.Q -> x.D (plus N-2 more grids on that net): race through and
          register to register; skew=NS clocks x that much later (race margin).
  key=value overrides a parameter of P (numbers in pF / ohm / V / ns as named).
Samples as dff_sweep: "1" above 118 V, "0" below 92 V for the next stage.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import latch_sweep as L
import dff_sweep as F


def rth(p):
    """Rt (to GND) and Rb (to -50 V) for rest level Vr and Thevenin resistance Rth"""
    k = -p['Vr'] / 50.0
    return p['Rth'] / (1 - k), p['Rth'] / k


def c1d(p):
    """C1 of the D pin's data grid behind the pin divider (C1rd when the grid sits behind Rd)"""
    if p.get('Rd'): return p['C1rd']
    return p['C1p'] if p['eg'] == 'g3' else p['C1g3']


def pff(t, d, ck, q, qn, p):
    """the cell: D inverter (half 6N16B), RS bistable, pulse network on g3.
    dhv = 1: D is an HV pin; the cell has its own dividers: D -> (C1a, Cd) -> S g1 (slow: the delay that keeps
    the new D off the gate until the pulse is over), D -> (C1g) -> inverter grid, inverter -> (C1c, Cd) -> R g1"""
    if p.get('dhv'):
        ps = dict(p, R1=p.get('R1s', p['R1']), R2=p.get('R2s', p['R2']))   # the slow dividers
        n = (L.div(f"{t}a", d, f"sd{t}", ps, p['C1a']) + f"CDS{t} sd{t} nb {p['Cd']}p\n"
             + L.div(f"{t}b", d, f"di{t}", p, p['C1g']) + F.inv(t, f"di{t}", f"dn{t}", p)
             + L.div(f"{t}i", f"dn{t}", f"r{t}", ps, p['C1c']) + f"CDR{t} r{t} nb {p['Cd']}p\n")
        s_, r_ = f"sd{t}", f"r{t}"
        rt, rb = rth(p)
        n += f"CC{t} {ck} g3{t} {p['Cc']}p\nRT{t} g3{t} 0 {rt:.0f}\nRB{t} g3{t} nb {rb:.0f}\n"
        c, lq, lqn = L.rslatch(t, s_, r_, f"g3{t}", q, qn, dict(p, Cb=p['Cb'] / 2 if p['Cb'] else 0))
        if p.get('La'):    # plate chokes in series with Ra (anode peaking, latch_peaking.py)
            for tag, node in (("q", q), ("n", qn)):
                c = c.replace(f"RA{t}{tag} vcc {node} {p['Ra']}\n",
                              f"RA{t}{tag} vcc ra{t}{tag} {p['Ra']}\nLA{t}{tag} ra{t}{tag} {node} {p['La']}\n")
        return n + c
    n = F.inv(t, d, f"dn{t}", p) + L.div(f"{t}i", f"dn{t}", f"r{t}", p, c1d(p))
    s_, r_ = d, f"r{t}"
    if p.get('Rd'):    # D delay: series Rd into each pentode g1, Cd from g1 to -50 V (hold against race through)
        n += f"RDS{t} {d} sd{t} {p['Rd']}\nCDS{t} sd{t} nb {p['Cd']}p\nRDR{t} r{t} rd{t} {p['Rd']}\nCDR{t} rd{t} nb {p['Cd']}p\n"
        s_, r_ = f"sd{t}", f"rd{t}"
    rt, rb = rth(p)
    n += f"CC{t} {ck} g3{t} {p['Cc']}p\nRT{t} g3{t} 0 {rt:.0f}\nRB{t} g3{t} nb {rb:.0f}\n"
    if p['eg'] == 'g3':
        pl = dict(p, Cb=p['Cb'] / 2 if p['Cb'] else 0)   # rslatch puts one Cb on each g3, both on g3x
    else:
        pl = dict(p, Cb=p['Cbd'])                        # Cb on each data g3 (holds it against Miller)
    c, lq, lqn = L.rslatch(t, s_, r_, f"g3{t}", q, qn, pl)
    return n + c


def drv_hv(wave, d, p):
    """HV net d: ideal HV source (inverted) -> divider -> 6N16B triode, Ra 10k; d is its plate"""
    return (f"VS{d} hs{d} 0 {wave}\n" + L.div(f"s{d}", f"hs{d}", f"is{d}", p, p['C1g'])
            + f"XD{d} {d} is{d} 0 pdx{d} nb 0 6N16B\nRD{d} vcc {d} 10k\nRDX{d} vcc pdx{d} 10k\n")


def clock(ct, cb, p, nm="ck", skew=0.0):
    """ideal HV clock line, rise/fall tr ns, source resistance Rs; skew ns later"""
    pts = [f"0 {150 if cb[0] else 50}"]
    tr = p['tr'] / 1000.0
    ct = [ct[0]] + [x + skew / 1000.0 for x in ct[1:]]
    for tt, b, pb in zip(ct[1:], cb[1:], cb[:-1]):
        if b != pb: pts += [f"{tt:.4f}u {150 if pb else 50}", f"{tt+tr:.4f}u {150 if b else 50}"]
    return f"V{nm} {nm}v 0 PWL({' '.join(pts)})\nR{nm} {nm}v {nm} {p['Rs']}\n"


def deck(kind, p, ngrid, per, dly):
    ct, cb, dt, db, samp, ref, stop = F.stimulus("dff", per, dly, "pos")
    if kind == "shift": ref = [0] + ref[:-1]
    s = f"* PFF {kind}\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    s += clock(ct, cb, p)
    if p.get('dhv'):     # HV D net: the driver plate itself
        s += drv_hv(F.wave(dt, db), "d", p)
    else:
        s += F.drv("d", dt, db, "d", p, c1d(p) + p['C1g'])
    if kind == "single":
        s += pff("x", "d", "ck", "q", "qn", p)
    else:
        s += pff("u", "d", "ck", "q1", "qn1", p)
        if p.get('dhv'):   # x.D is the HV net q1 itself; the other N-2 grids on their own divider
            s += L.div("y1", "q1", "dl1", p, p['C1g'] * max(ngrid - 2, 1)) + L.loads("dl1", p, max(ngrid - 2, 0), "y")
            s += L.div("y2", "qn1", "dn1", p, p['C1g'] * ngrid) + L.loads("dn1", p, ngrid, "z")
            ckx = "ck"
            if p.get('skew'): s += clock(ct, cb, p, "ckx", p['skew']); ckx = "ckx"   # x clocked later: race test
            s += pff("x", "q1", ckx, "q", "qn", p)
            return finish(s, p, ngrid, samp, ref, stop, per)
        s += L.div("y1", "q1", "d1", p, c1d(p) + p['C1g'] + p['C1g'] * max(ngrid - 2, 0))
        s += L.loads("d1", p, max(ngrid - 2, 0), "y") + L.div("y2", "qn1", "dn1", p, p['C1g'] * ngrid)
        s += L.loads("dn1", p, ngrid, "z")
        s += pff("x", "d1", "ck", "q", "qn", p)
    return finish(s, p, ngrid, samp, ref, stop, per)


def finish(s, p, ngrid, samp, ref, stop, per):
    s += L.div("yq", "q", "yq", p, p['C1g'] * ngrid) + L.div("yn", "qn", "yn", p, p['C1g'] * ngrid)
    s += L.loads("yq", p, ngrid, "q") + L.loads("yn", p, ngrid, "n")
    m = [f"meas tran q{k} find v(q) at={t:.4f}u" for k, t in enumerate(samp)]
    m += [f"meas tran n{k} find v(qn) at={t:.4f}u" for k, t in enumerate(samp)]
    m += [f"meas tran {x}min min v({x}) from=0.5u to={stop}u" for x in ("g3x", "d", "yq", "fqx", "fqnx", "rx", "sdx")]
    m += [f"meas tran g3max max v(g3x) from=0.5u to={stop}u"]
    # pulse width on g3x above -5 V, and clock-to-Q (HV clock 100 V to Q 100 V) of the first Q rise after 3 periods
    t3 = 3 * per + 0.1
    m += [f"meas tran pw trig v(g3x) val=-5 rise=1 td={t3:.3f}u targ v(g3x) val=-5 fall=1 td={t3:.3f}u"]
    m += [f"meas tran tcq_r trig v(ck) val=100 rise=1 td={t3:.3f}u targ v(q) val=100 rise=1 td={t3:.3f}u"]
    m += [f"meas tran tcq_f trig v(ck) val=100 rise=1 td={t3:.3f}u targ v(q) val=100 fall=1 td={t3:.3f}u"]
    s += f".options method=gear\n.tran 2n {stop:.3f}u\n.control\nrun\n" + "\n".join(m) + "\n.endc\n.end\n"
    return s, ref


def run(arg):
    kind, name, p, n, per, dly = arg
    s, ref = deck(kind, p, n, per, dly)
    fn = os.path.join(tempfile.gettempdir(), f"pff_sweep_{os.getpid()}.cir")
    open(fn, "w").write(s)
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True, timeout=180).stdout
    m = {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}
    return kind, name, n, per, m, ref


def fmt(kind, name, n, per, m, ref):
    q = [m.get(f"q{k}", float('nan')) for k in range(len(ref))]
    qn = [m.get(f"n{k}", float('nan')) for k in range(len(ref))]
    good = lambda v, b: v > 118 if b else v < 92
    bad = [k for k, r in enumerate(ref) if k >= 3 and not (good(q[k], r) and good(qn[k], not r))]
    hi = min([x for x, r in zip(q[3:], ref[3:]) if r] + [x for x, r in zip(qn[3:], ref[3:]) if not r])
    lo = max([x for x, r in zip(q[3:], ref[3:]) if not r] + [x for x, r in zip(qn[3:], ref[3:]) if r])
    g = lambda k, s=1: m.get(k, float('nan')) * s
    return (f"{kind:6s} {name:18s} N={n:2d} T={per:5.2f}us {'OK  ' if not bad else 'ERR' + str(len(bad))} | hi {hi:5.1f} lo {lo:5.1f}"
            f" | g3 {g('g3xmin'):5.1f}..{g('g3max'):4.1f} pw {g('pw',1e9):4.0f} | min s {g('sdxmin'):5.1f} r {g('rxmin'):5.1f}"
            f" fb {min(g('fqxmin'), g('fqnxmin')):5.1f} | tcq {g('tcq_r',1e9):4.0f}/{g('tcq_f',1e9):4.0f} ns")


# the chosen point (doc/tc_n5_pulse_dff.md §4): HV D pin with slow in-cell dividers 150k / 62k (no C1), plate chokes
# 1 mH, Rg2 12k, Cc 3.9 pF, g3 rest -12.4 V from 43k / 130k (Thevenin 32.3k). The other keys are the options of §3.
P = dict(L.BASE, **L.CHOSEN, Cc=3.9, Vr=-12.4, Rth=32.3e3, Cb=0, tr=30, Rs=100, Rd=0, Cd=0.001, Cbd=15, C1rd=1.0,
         dhv=1, C1a=0.001, C1c=0.001, R1s="150k", R2s="62k", La="1m", Rg2="12k")

if __name__ == "__main__":
    args = sys.argv[1:]
    kind = args.pop(0) if args and args[0] in ("single", "shift") else "single"
    per, dly = 4.0, 0.25
    if "--period" in args: i = args.index("--period"); per = float(args[i + 1]); del args[i:i + 2]
    if "--dly" in args: i = args.index("--dly"); dly = float(args[i + 1]); del args[i:i + 2]
    p = dict(P)
    for a in [a for a in args if "=" in a]:
        k, v = a.split("=", 1); p[k] = float(v) if re.match(r"^-?[\d.]+(e-?\d+)?$", v) else v
    grids = [int(x) for x in args if "=" not in x] or [2, 6, 10]
    jobs = [(kind, " ".join(a for a in args if "=" in a) or "base", p, n, per, dly) for n in grids]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
