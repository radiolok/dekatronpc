#!/usr/bin/env python3
"""Build every figure of the DFFP2_J2N16 page (sch/logic/DFFP2_J2N16/README.md) from the sources in the repo.

usage: tools/spice/pff_plots.py [OUT_DIR]          (default: sch/logic/DFFP2_J2N16/img)

Writes
  dffp_core.png, dffp2_cell.png, dffp2_tb.png   the sheets exported from KiCad (one flip-flop, the cell, the bench)
  dffp2_tran.png                                the KiCad testbench waveforms (ngspice)
  dffp_fanout.png                               C->Q, setup, hold and the shortest pulse against fanout
and prints the testbench check and the numbers behind the fanout chart (pff_timing.py, about 10 minutes).
Needs kicad-cli, rsvg-convert, matplotlib, Pillow and KiCad's libngspice. Style as tools/spice/latch_plots.py.
"""
import os, sys, tempfile
from multiprocessing import Pool
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import latch_plots as LP   # noqa: E402  (style, crop_png, kicad_waves, wave_fig)
import pff_tb as TB        # noqa: E402
import pff_timing as T     # noqa: E402
import pff_sweep as PS     # noqa: E402

CELL = "DFFP2_J2N16"
GRIDS = (2, 4, 6)


def schematics(out, tmp):
    import subprocess
    svg = os.path.join(tmp, "svg"); os.makedirs(svg, exist_ok=True)
    subprocess.run(["kicad-cli", "sch", "export", "svg", "-e", "-o", svg,
                    os.path.join(LP.SCH, CELL, CELL + "_tb.kicad_sch")], check=True, capture_output=True)
    for s, png, w in ((f"{CELL}_tb-DUT-FF1.svg", "dffp_core.png", 3000), (f"{CELL}_tb-DUT.svg", "dffp2_cell.png", 3000),
                      (f"{CELL}_tb.svg", "dffp2_tb.png", 2600)):
        LP.crop_png(os.path.join(svg, s), os.path.join(out, png), width=w)


def waveforms(out, tmp):
    tb = TB.bench()
    m, t, v = LP.kicad_waves(CELL + "_tb", ["/CK", "/D1", "/DUT/FF1/G", "/DUT/FF1/S", "/Q1", "/Q2"], tmp)
    rows = [("CK (HV clock line, 500 kHz)", v[0], "hv"), ("D1 (HV, from the driver plate)", v[1], "hv"),
            ("G of FF1 (LV: both g3, the pulse)", v[2], "lv"), ("S of FF1 (LV: QN pentode g1, behind 150k / 62k)", v[3], "lv"),
            ("Q1 (HV) = D2", v[4], "hv"), ("Q2 (HV)", v[5], "hv")]
    LP.wave_fig(os.path.join(out, "dffp2_tran.png"),
                "DFFP2_J2N16: KiCad testbench in ngspice, shift register, fanout 6", t, rows)
    bad = TB.check(tb, m)
    print(f"testbench: {len(m)} values, sampling errors: {bad or 'none'}; pulse {m.get('pw', 0)*1e9:.0f} ns, "
          f"lowest G {min(m.get('g1min', 0), m.get('g2min', 0)):.1f} V; C->Q Q1 {m['tcq_q1r']*1e9:.0f}/{m['tcq_q1f']*1e9:.0f} ns,"
          f" Q2 {m['tcq_q2r']*1e9:.0f}/{m['tcq_q2f']*1e9:.0f} ns")
    return m


def job(a):
    kind, n, init, v = a
    return a, T.run((kind, dict(PS.P), n, init, v))


def timing():
    """C->Q to 100 V, setup / hold (worst of four cases) and the shortest pulse at each fanout"""
    jobs = [(k, n, 0, 1) for n in GRIDS for k in ("wmin", "tcq", "tcqth")]
    jobs += [(k, n, i, v) for n in GRIDS for k in ("hold", "setup") for i, v in ((0, 1), (1, 1), (0, 0), (1, 0))]
    with Pool(16) as pool:
        res = dict(pool.map(job, jobs))
    r = {}
    for n in GRIDS:
        _, _, _, _, x, m = res[("wmin", n, 0, 1)]
        tq = res[("tcq", n, 0, 1)][5]; th = res[("tcqth", n, 0, 1)][5]
        # on the D pin (dt: clock line to D pin, both at 100 V) where measured, else at the source
        pin = lambda r_: r_[5].get('dt', float('nan')) * 1e9 if r_[5].get('dt') is not None else r_[4] * 1e3
        hold = max(pin(res[("hold", n, i, v)]) for i, v in ((0, 1), (1, 1), (0, 0), (1, 0))
                   if res[("hold", n, i, v)][5].get('dt') is not None)
        setup = max(pin(res[("setup", n, i, v)]) for i, v in ((0, 1), (1, 1), (0, 0), (1, 0)))
        r[n] = dict(wmin=m.get('pw', float('nan')) * 1e9, cq_rise=tq['set'][0], cq_fall=tq['rst'][0],
                    th_rise=th['set'][0], th_fall=th['rst'][0], setup=setup, hold=hold)
        print(f"fanout {n}: " + ", ".join(f"{k} {v:.0f}" for k, v in r[n].items()))
    return r


def fanout_fig(path, r):
    fig, axs = plt.subplots(1, 2, figsize=(10, 3.8), constrained_layout=True)
    x = list(GRIDS)
    ax = axs[0]
    for key, lab, c in (("cq_rise", "C→Q, Q rises (100 V)", LP.BLUE), ("cq_fall", "C→Q, Q falls (100 V)", LP.ORANGE),
                        ("wmin", "shortest pulse", LP.GREEN)):
        y = [r[n][key] for n in x]
        ax.plot(x, y, color=c, lw=2, marker="o"); ax.text(x[-1] + 0.1, y[-1], lab, va="center", fontsize=8, color=c)
    ax.set_title("Delays", loc="left"); ax.set_xlabel("grids on each output"); ax.set_ylabel("ns"); ax.set_xlim(1.5, 8.5)
    ax = axs[1]
    for key, lab, c in (("setup", "setup", LP.BLUE), ("hold", "hold", LP.ORANGE)):
        y = [r[n][key] for n in x]
        ax.plot(x, y, color=c, lw=2, marker="o"); ax.text(x[-1] + 0.1, y[-1], lab, va="center", fontsize=8, color=c)
    ax.axhline(0, color=LP.MUTED, ls=(0, (4, 3)), lw=1)
    ax.set_title("Timing limits (worst of four cases, D pin vs clock line, 100 V)", loc="left", fontsize=9)
    ax.set_xlabel("grids on each output"); ax.set_ylabel("ns"); ax.set_xlim(1.5, 8.5)
    fig.suptitle("DFFP_J2N16 against fanout (SPICE, tools/spice/pff_timing.py)", x=0.01, ha="left", fontsize=12)
    fig.savefig(path, dpi=105); plt.close(fig)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(LP.SCH, CELL, "img")
    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        schematics(out, tmp)
        waveforms(out, tmp)
    fanout_fig(os.path.join(out, "dffp_fanout.png"), timing())
