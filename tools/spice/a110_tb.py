#!/usr/bin/env python3
"""A110 dekatron SPICE testbench (sch/libs/A110.sub, doc/dekatron_physics.md).

Circuit: anode supply E through Ra (+ Cw wiring capacitance), each main cathode through its own read
resistor Rk to a return node that a write pulls to -WRV (write = negative pulse on the target cathode,
Lipkin fig. 20 v-d, Yablonsky 3-2 method 3), guides G1/G2 at bias +VG through RG, a control pulse takes
a guide to VG - AMP (sheet: 38 V).

Commands
  seq                  operation sequence vs the RTL ring model (DekatronTubeV2 rules), one op per 10 us Clk
  sweep {pw,gap,rate,write} [model params]   threshold sweeps; prints a table
  plot [file.png]      waveforms of one +1 and one -1 (default doc/img/a110_spice_step.png)
Parameters NAME=value: circuit ones (E, RA, CW, RK, VG, AMP, RG, WRV) change the testbench, the rest
go to the subcircuit instance (e.g. TD=1u UT1=5).
"""
import os
import re
import subprocess
import sys
import tempfile
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.abspath(os.path.join(HERE, "..", "..", "sch", "libs", "A110.sub"))

CIRCUIT = dict(E=350, RA="180k", CW="3p", RK="15k", VG=19, AMP=38, RG="1k", WRV=150)
SLOT = 10e-6        # machine Clk 100 kHz: one operation per slot
PD = 1e-6           # phase start inside the slot
PW = 600e-9         # guide phase width (tube build, synth_sim -t)
OV = 50e-9          # phase B starts OV before phase A ends (REQ-PULSE-008: touch or overlap)
WRW = 5e-6          # write pulse width (DEKATRON_WRITE_MIN_NS)
T0 = 60e-6          # power-up ramp and settling before the first slot


class Stim:
    """piecewise-linear stimulus for G1, G2 and the ten cathode return nodes"""

    def __init__(self):
        self.ev = {n: [] for n in ["g1", "g2"] + [f"r{k}" for k in range(10)]}

    def pulse(self, node, t0, t1):
        self.ev[node].append((t0, t1))

    def pwl(self, node, idle, active, tr=20e-9):
        pts = [(0.0, idle)]
        for t0, t1 in sorted(self.ev[node]):
            pts += [(t0, idle), (t0 + tr, active), (t1, active), (t1 + tr, idle)]
        return "PWL(" + " ".join(f"{t:.4e} {v}" for t, v in pts) + ")"


def op_into(st, op, t, pw=PW, gap=-OV, wrw=WRW):
    """schedule one machine operation in the slot starting at t"""
    a0 = t + PD
    if op == "inc":                           # A then B: +1
        st.pulse("g1", a0, a0 + pw)
        st.pulse("g2", a0 + pw + gap, a0 + 2 * pw + gap)
    elif op == "dec":                         # B then A: -1
        st.pulse("g2", a0, a0 + pw)
        st.pulse("g1", a0 + pw + gap, a0 + 2 * pw + gap)
    elif op == "A":                           # A alone: back to the same cathode
        st.pulse("g1", a0, a0 + pw)
    elif op == "B":
        st.pulse("g2", a0, a0 + pw)
    elif op.startswith("w"):                  # write digit k
        st.pulse(f"r{int(op[1:])}", t + PD, t + PD + wrw)
    elif op != "nop":
        raise ValueError(op)


def deck(st, stop, params, probes):
    c = dict(CIRCUIT)
    c.update({k: (float(v) if k in ("E", "VG", "AMP", "WRV") else v) for k, v in params.items() if k in CIRCUIT})
    m = " ".join(f"{k}={v}" for k, v in params.items() if k not in CIRCUIT)
    s = [f"* A110 testbench", f".include {MODEL}",
         f"VE e 0 PWL(0 0 {T0 / 3:.3e} {c['E']})",
         f"RA e a {c['RA']}", f"CW a 0 {c['CW']}",
         f"VG1 vg1 0 {st.pwl('g1', c['VG'], c['VG'] - c['AMP'])}",
         f"VG2 vg2 0 {st.pwl('g2', c['VG'], c['VG'] - c['AMP'])}",
         f"RG1 vg1 g1 {c['RG']}", f"RG2 vg2 g2 {c['RG']}"]
    for k in range(10):
        s += [f"VR{k} r{k} 0 {st.pwl(f'r{k}', 0, -c['WRV'])}", f"RK{k} k{k} r{k} {c['RK']}"]
    s += [f"XT a {' '.join(f'k{k}' for k in range(10))} g1 g2 A110 {m}",
          f".options method=gear reltol=1e-4 abstol=1e-12 vntol=1e-5 itl4=100",
          f".tran 10n {stop:.4e} 0 20n", ".control", "run"]
    s += probes
    s += [".endc", ".end"]
    return "\n".join(s) + "\n"


def run_deck(text):
    with tempfile.NamedTemporaryFile("w", suffix=".cir", delete=False) as f:
        f.write(text)
        fn = f.name
    try:
        o = subprocess.run([sys.executable, NGRUN, fn], capture_output=True, text=True, timeout=1800)
    finally:
        os.unlink(fn)
    return o.stdout + o.stderr


def lit_probes(times):
    """cathode currents (mA) at the given times"""
    rk = CIRCUIT["RK"].replace("k", "e3")
    L = [f"let ik{k} = (v(k{k})-v(r{k}))/{rk}*1e3" for k in range(10)]
    for j, t in enumerate(times):
        for k in range(10):
            L.append(f"meas tran i{j}_{k} find ik{k} at={t:.4e}")
    return L


def parse_lit(out, n):
    val = {m.group(1): float(m.group(2)) for m in re.finditer(r"^(i\d+_\d+)\s*=\s*([-+0-9.eE]+)", out, re.M)}
    res = []
    for j in range(n):
        cur = [val.get(f"i{j}_{k}", float("nan")) for k in range(10)]
        lit = [k for k, i in enumerate(cur) if i > 0.3]
        res.append((lit, max(cur)))
    return res


def rtl_model(ops, start):
    """the RTL ring rules (DekatronTubeV2): inc +1, dec -1, single phase returns, write sets"""
    d, out = start, []
    for op in ops:
        if op == "inc":
            d = (d + 1) % 10
        elif op == "dec":
            d = (d - 1) % 10
        elif op.startswith("w"):
            d = int(op[1:])
        out.append(d)
    return out


def sequence(params, ops=None):
    ops = ops or ["w0", "inc", "inc", "inc", "dec", "A", "B", "nop", "w7", "inc", "inc", "inc", "dec", "dec"]
    st = Stim()
    for n, op in enumerate(ops):
        op_into(st, op, T0 + n * SLOT)
    times = [T0 - 1e-6] + [T0 + (n + 1) * SLOT - 0.5e-6 for n in range(len(ops))]
    out = run_deck(deck(st, T0 + len(ops) * SLOT, params, lit_probes(times)))
    res = parse_lit(out, len(times))
    if any(c != c for _, c in res):
        print(out[-3000:])
        raise SystemExit("simulation failed")
    p0 = res[0][0]
    print(f"power-up: lit {p0}, Ik {res[0][1]:.3f} mA")
    exp = rtl_model(ops, p0[0] if p0 else 0)
    bad = 0
    for op, (lit, i), e in zip(ops, res[1:], exp):
        ok = lit == [e]
        bad += not ok
        print(f"{op:4} -> lit {lit}  Ik {i:.3f} mA   RTL {e}  {'ok' if ok else 'MISMATCH'}")
    print(f"{len(ops) - bad}/{len(ops)} match the RTL model")
    return bad


def one_step(args):
    """start on K0 (written), then one op; returns the lit cathode(s) at the end of the slot"""
    kind, val, params = args
    st = Stim()
    op_into(st, "w0", T0)
    t = T0 + SLOT
    if kind == "pw":                      # one +1 with phase width val
        op_into(st, "inc", t, pw=val)
        n_ops = 1
    elif kind == "gap":                   # A, then B after a gap val (negative = overlap)
        op_into(st, "inc", t, gap=val)
        n_ops = 1
    elif kind == "rate":                  # 9 back-to-back +1 at a period val (3 slices: A, B, pause)
        pw = val / 3
        for n in range(9):
            a0 = t + PD + n * val
            st.pulse("g1", a0, a0 + pw)
            st.pulse("g2", a0 + pw - min(OV, pw / 4), a0 + 2 * pw - min(OV, pw / 4))
        n_ops = 1
    elif kind == "write":                 # write 5 with width val
        op_into(st, "w5", t, wrw=val)
        n_ops = 1
    stop = t + SLOT * n_ops + (9 * val if kind == "rate" else 0)
    out = run_deck(deck(st, stop, params, lit_probes([stop - 0.3e-6])))
    return parse_lit(out, 1)[0]


SWEEPS = {
    "pw": ([30e-9, 50e-9, 80e-9, 100e-9, 150e-9, 200e-9, 300e-9, 600e-9, 1e-6], "phase width", 1),
    "gap": ([-300e-9, -100e-9, 0, 50e-9, 100e-9, 200e-9, 300e-9, 500e-9, 1e-6], "gap A->B", 1),
    "rate": ([0.3e-6, 0.45e-6, 0.6e-6, 0.9e-6, 1.2e-6, 1.8e-6, 3e-6], "period", 9),
    "write": ([0.2e-6, 0.5e-6, 1e-6, 2e-6, 3e-6, 5e-6], "write width", 5),
}


def sweep(kind, params):
    vals, label, expect = SWEEPS[kind]
    with Pool(min(len(vals), os.cpu_count() or 1)) as p:
        res = p.map(one_step, [(kind, v, params) for v in vals])
    print(f"{label:>12}  lit   (expected {expect})")
    for v, (lit, i) in zip(vals, res):
        print(f"{v * 1e9:10.0f} ns  {lit}  Ik {i:.3f} mA  {'ok' if lit == [expect] else '--'}")


def plot(fn, params):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    st = Stim()
    op_into(st, "w0", T0)
    op_into(st, "inc", T0 + SLOT)
    op_into(st, "dec", T0 + 2 * SLOT)
    t0, t1 = T0 + SLOT, T0 + 3 * SLOT
    dat = tempfile.NamedTemporaryFile(suffix=".dat", delete=False).name
    rk = CIRCUIT["RK"].replace("k", "e3")
    probes = [f"let ik{k} = (v(k{k})-v(r{k}))/{rk}*1e3" for k in (0, 1)]
    probes += [f"linearize v(a) v(g1) v(g2) ik0 ik1", f"wrdata {dat} v(a) v(g1) v(g2) ik0 ik1"]
    run_deck(deck(st, t1, params, probes).replace(".tran 10n", ".tran 5n"))
    d = np.loadtxt(dat)
    os.unlink(dat)
    tt = d[:, 0]
    sel = (tt >= t0) & (tt <= t1)
    tt = (tt[sel] - t0) * 1e6
    fig, ax = plt.subplots(3, 2, figsize=(11, 7), sharex="col", gridspec_kw={"height_ratios": [2, 1, 1]})
    for c, (lo, hi, title) in enumerate([(0.5, 3.5, "+1 (A, then B)"), (10.5, 13.5, "-1 (B, then A)")]):
        w = (tt >= lo) & (tt <= hi)
        ax[0, c].plot(tt[w], d[sel, 1][w], label="anode")
        ax[0, c].set_ylabel("V")
        ax[0, c].set_title(title)
        ax[1, c].plot(tt[w], d[sel, 3][w], label="G1 (guide A)")
        ax[1, c].plot(tt[w], d[sel, 5][w], label="G2 (guide B)")
        ax[1, c].set_ylabel("V")
        ax[2, c].plot(tt[w], d[sel, 7][w], label="K0")
        ax[2, c].plot(tt[w], d[sel, 9][w], label="K1")
        ax[2, c].set_ylabel("Ik, mA")
        ax[2, c].set_xlabel("t, us from the start of the Clk slot")
        for a in ax[:, c]:
            a.grid(alpha=0.3)
            a.legend(loc="right", fontsize=8)
    fig.suptitle("A110 SPICE model (sch/libs/A110.sub): Ra 180k from 350 V, Rk 15k, guides +19 V, pulse 38 V, 600 ns")
    fig.tight_layout()
    fig.savefig(fn, dpi=110)
    print(fn)


if __name__ == "__main__":
    args = sys.argv[1:]
    params = dict(a.split("=", 1) for a in args if "=" in a)
    words = [a for a in args if "=" not in a]
    if not words or words[0] == "seq":
        sys.exit(1 if sequence(params) else 0)
    if words[0] == "sweep":
        sweep(words[1], params)
    if words[0] == "plot":
        plot(words[1] if len(words) > 1 else os.path.join(HERE, "..", "..", "doc", "img", "a110_spice_step.png"), params)
