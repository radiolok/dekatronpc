#!/usr/bin/env python3
"""DFF_J2N16 with an asynchronous clear or preset through 6Kh7B diodes (owner's idea, 2026-10-29;
sch/logic/DFF_J2N16/README.md, sch/tubes/6Kh7B/README.md).

One 6Kh7B per flip-flop: a diode from the reset line (anode) into a cross-coupled triode grid of each latch.
  clear  (DFFRN): into FQN of master and slave, the grid of the triode on plate Q -> Q = 0
  preset (DFFSN): into FQ of master and slave -> Q = 1
The line is not an LV net: it idles at VIDLE (-20 V, the owner's choice) and is pulled to GND while the reset
holds (a relay contact); its logic name is RN / SN, active low: RN = 0 is the line at GND.

usage: dffr_sweep.py normal [grids...]    two flops in a row at 1 MHz, the line idle: does the diode disturb them?
       dffr_sweep.py async  [grids...]    assert / hold / release, Q against C, clear and preset
       dffr_sweep.py recovery [grids...]  shortest time from releasing the line to the falling edge of C
options: --idle V (-20), --model leaky|nom (diode model case, default leaky = the sheet's bound), --cak PF (5.8),
         --comp PF (Cc across the feedback divider's C1, 0 = none)
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import latch_sweep as L   # noqa: E402
import dff_sweep as D     # noqa: E402
import fit_6kh7b as K     # noqa: E402

P = dict(L.BASE, **L.CHOSEN, edge="neg")
OPT = dict(idle=-20.0, model="leaky", cak=5.8, comp=0.0)
FALL, RISE = 92, 118
DFF = D.dff   # the plain flip-flop; normal() swaps D.dff for the one with diodes while D.deck builds


def kh7b_sub():
    path = os.path.join(tempfile.gettempdir(), f"6kh7b_{OPT['model']}_{OPT['cak']}.sub")
    open(path, "w", newline="").write(K.sub_text(K.vc_for(K.I0[OPT['model']]), OPT['model']).replace("CAK=5.8P", f"CAK={OPT['cak']}P"))
    return path


def dffr(t, d, c, q, qn, p, mode, line):
    """DFF_J2N16 plus the two reset diodes; mode 'clr' or 'pre'"""
    n = DFF(t, d, c, q, qn, p)
    node = "fqn" if mode == "clr" else "fq"
    n += f"XKA{t} {line} {node}{t}m 6Kh7B\nXKB{t} {line} {node}{t}s 6Kh7B\n"
    if OPT['comp']:
        # the diode's A-K capacitance hangs on the feedback node from a static line: compensate the feedback
        # divider with Cc in parallel to its C1 (plate -> node), Cc ~ CAK x R2 / R1
        src_m, src_s = (f"qnm{t}", qn) if mode == "clr" else (f"qm{t}", q)
        n += f"CCA{t} {src_m} {node}{t}m {OPT['comp']}p\nCCB{t} {src_s} {node}{t}s {OPT['comp']}p\n"
    return n


def head():
    return (f"* DFF with reset diodes\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\n.include {kh7b_sub()}\n"
            "VCC vcc 0 150\nVNB nb 0 -50\n")


def ngspice(deck):
    fn = os.path.join(tempfile.gettempdir(), f"dffr_{os.getpid()}.cir")
    open(fn, "w").write(deck)
    o = subprocess.run([sys.executable, L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


# ------------------------------------------------------------- (a) normal operation, line idle
def normal(arg):
    mode, n = arg
    D.dff = lambda t, d, c, q, qn, p: dffr(t, d, c, q, qn, p, mode, "rst")
    try:
        s, ref = D.deck("shift", P, n, 1.0, 0.25)
    finally:
        D.dff = DFF
    s = s.replace("VCC vcc 0 150\n", f"VCC vcc 0 150\n.include {kh7b_sub()}\nVRST rst 0 {OPT['idle']}\n", 1)
    s = s.replace("\n.endc", "\nmeas tran irst avg i(VRST) from=3u to=19u\n.endc")
    m = ngspice(s)
    return mode, n, D.fmt("shift", f"{mode} idle {OPT['idle']:.0f}", n, 1.0, m, ref), m.get("irst", float('nan'))



# ------------------------------------------------------------- (b) assert, hold, release
def async_deck(mode, n, t_set, t_rel, per=1.0, dly=0.25, d_bit=None, extra=""):
    """C at 1 MHz (high in the first half); D = d_bit (1 for clear: Q was 1; 0 for preset);
    the line goes to GND at t_set and back to idle at t_rel (20 ns edges)."""
    d_bit = (1 if mode == "clr" else 0) if d_bit is None else d_bit
    stop = t_rel + 4 * per
    k = int(stop / per) + 2
    ct, cb = [0.0], [0]
    for i in range(k): ct += [i * per + per / 2, (i + 1) * per]; cb += [1, 0]
    # C high in the second half of each period here: rises at i*per + per/2, falls at (i+1)*per
    s = head()
    s += D.drv("c", ct, cb, "c", P, 2 * P['C1g3'] + P['C1g']) + D.drv("d", [0.0], [d_bit], "d", P, P['C1p'] + P['C1g'])
    s += f"VRST rst 0 PWL(0 {OPT['idle']} {t_set}u {OPT['idle']} {t_set + 0.02}u 0 {t_rel}u 0 {t_rel + 0.02}u {OPT['idle']})\n"
    s += dffr("x", "d", "c", "q", "qn", P, mode, "rst")
    s += L.div("yq", "q", "yq", P, P['C1g'] * n) + L.div("yn", "qn", "yn", P, P['C1g'] * n)
    s += L.loads("yq", P, n, "q") + L.loads("yn", P, n, "n")
    s += f".tran 5n {stop:.3f}u\n.control\nrun\n{extra}.endc\n.end\n"
    return s


def async_run(arg):
    mode, n = arg
    out = []
    want_q = 0 if mode == "clr" else 1
    dq = ("fall", FALL) if mode == "clr" else ("rise", RISE)
    for phase, t_set in (("C high", 4.7), ("C low", 5.2)):    # C rises at 4.5, falls at 5.0, rises at 5.5
        t_rel = t_set + 3.0
        ex = (f"meas tran q_before find v(q) at={t_set - 0.05}u\n"
              f"meas tran t_q trig v(rst) val={OPT['idle'] / 2} rise=1 targ v(q) val={dq[1]} {dq[0]}=1\n"
              f"meas tran qmax max v(q) from={t_set + 0.8}u to={t_rel}u\nmeas tran qmin min v(q) from={t_set + 0.8}u to={t_rel}u\n"
              f"meas tran q_after find v(q) at={t_rel + 0.9}u\nmeas tran q_next find v(q) at={t_rel + 2.4}u\n"
              f"meas tran irst min i(VRST) from={t_set + 0.5}u to={t_rel}u\n"
              f"meas tran fmin min v(fqnxm) from=0.5u to={t_rel + 3}u\nmeas tran fmax max v(fqnxm) from=0.5u to={t_rel + 3}u\n")
        m = ngspice(async_deck(mode, n, t_set, t_rel, extra=ex))
        g = lambda k, s=1: m.get(k, float('nan')) * s
        held = (g('qmax') < FALL) if want_q == 0 else (g('qmin') > RISE)
        out.append(f"{mode} N={n:2d} assert at {phase:6s}: Q before {g('q_before'):5.1f} -> {'held' if held else 'NOT HELD'}"
                   f" ({g('qmin'):5.1f}..{g('qmax'):5.1f} V while C toggles), assert->Q {g('t_q', 1e9):4.0f} ns,"
                   f" line {abs(g('irst', 1e3)):4.2f} mA; after release Q {g('q_after'):5.1f}, after the next C fall {g('q_next'):5.1f}")
    return "\n".join(out)


# ------------------------------------------------------------- (c) recovery: release before the falling edge of C
def recovery_ok(mode, n, gap):
    """release the line `gap` us before a falling edge of C (at 9.0 us); D = ~reset value. True if that edge
    already captures D (Q valid one period later)."""
    t_rel = 9.0 - gap
    ex = f"meas tran q_cap find v(q) at={9.0 + 0.95}u\n"
    m = ngspice(async_deck(mode, n, 5.2, t_rel, extra=ex))
    v = m.get("q_cap", float('nan'))
    return (v > RISE) if mode == "clr" else (v < FALL), v


def recovery(arg):
    mode, n = arg
    lo, hi = 0.0, 0.5        # gap in us: lo fails, hi passes
    ok_hi, _ = recovery_ok(mode, n, hi)
    if not ok_hi: return f"{mode} N={n:2d} recovery: fails even at {hi * 1e3:.0f} ns"
    ok_lo, _ = recovery_ok(mode, n, lo)
    if ok_lo: return f"{mode} N={n:2d} recovery: passes at 0 ns"
    for _ in range(7):
        mid = (lo + hi) / 2
        ok, _ = recovery_ok(mode, n, mid)
        lo, hi = (lo, mid) if ok else (mid, hi)
    return f"{mode} N={n:2d} recovery (release before C falls): >= {hi * 1e3:.0f} ns (fails at {lo * 1e3:.0f} ns)"


if __name__ == "__main__":
    args = sys.argv[1:]
    what = args.pop(0) if args else "normal"
    for flag, key, conv in (("--idle", "idle", float), ("--model", "model", str), ("--cak", "cak", float), ("--comp", "comp", float)):
        if flag in args: i = args.index(flag); OPT[key] = conv(args[i + 1]); del args[i:i + 2]
    grids = [int(x) for x in args] or [2, 6, 10]
    jobs = [(mode, n) for mode in ("clr", "pre") for n in grids]
    fn = {"normal": normal, "async": async_run, "recovery": recovery}[what]
    with Pool(6) as pool:
        for r in pool.map(fn, jobs):
            if what == "normal":
                mode, n, line, irst = r; print(line, f"| line idle current {irst * 1e6:+.2f} uA")
            else:
                print(r)
