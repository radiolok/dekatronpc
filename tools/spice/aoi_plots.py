#!/usr/bin/env python3
"""Build every figure of the A1OOI_N16J2, A2OOI_J2 and NOR4_N16 cell pages from the sources in the repo.

usage: tools/spice/aoi_plots.py [OUT_DIR]          (default: each figure into sch/logic/<CELL>/img)

Writes, per cell (prefix aoi21_ for A1OOI_N16J2, aoi22_ for A2OOI_J2, nor4_ for NOR4_N16):
  <p>cell.png, <p>tb.png   the cell sheet and the testbench root sheet, exported from KiCad
  <p>tran.png              KiCad testbench waveforms (ngspice)
  <p>vtc.png               static transfer: Y against the HV net of each input, the others enabling
  <p>fanout.png            delay of every arc against fanout (aoi_sweep.py)
Needs kicad-cli, rsvg-convert, matplotlib, Pillow and KiCad's libngspice. Style and helpers as latch_plots.py.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import latch_plots as LP   # noqa: E402  (rcParams, crop_png, kicad_waves, wave_fig, colours)
import aoi_sweep as A      # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

REPO = LP.REPO
CELL = {"a1": ("A1OOI_N16J2", "aoi21_"), "a22": ("A2OOI_J2", "aoi22_"), "n4": ("NOR4_N16", "nor4_"), "o4": ("OR4_N16", "or4_")}
GRIDS = (2, 4, 6, 8, 10)
HV = {0: 55.0, 1: 146.9}


def dest(out, key, png):
    d = out or os.path.join(REPO, "sch", "logic", CELL[key][0], "img")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, CELL[key][1] + png)


def schematics(out, tmp):
    for key, (name, _) in CELL.items():
        tb = name + "_tb"; svg = os.path.join(tmp, tb); os.makedirs(svg, exist_ok=True)
        subprocess.run(["kicad-cli", "sch", "export", "svg", "-e", "-o", svg,
                        os.path.join(REPO, "sch", "logic", name, tb + ".kicad_sch")], check=True, capture_output=True)
        LP.crop_png(os.path.join(svg, tb + "-DUT.svg"), dest(out, key, "cell.png"), width=3000)
        LP.crop_png(os.path.join(svg, tb + ".svg"), dest(out, key, "tb.png"), width=2600)


def waveforms(out, tmp):
    res = {}
    for key, (name, _) in CELL.items():
        c = A.CELLS[key]
        pins = [p + "1" for p in c['pins']] if key == "a1" else list(c['pins'])
        y = "Y1" if key == "a1" else "Y"
        lv = c.get('out') == "LV"
        second = f"/PL_{y}0a" if lv else f"/{y}_LV"
        r, t, v = LP.kicad_waves(name + "_tb", [f"/{p}" for p in pins] + [f"/{y}", second], LP_TMP(tmp))
        grid = {"g1": "g1", "g3": "g3", "tri": "triode grid", "fol": "follower grid"}
        rows = [(f"{p} (LV, {grid[c['grid'][q]]})", v[i], "lv") for i, (p, q) in enumerate(zip(pins, c['pins']))]
        if lv:
            rows += [(f"{y} (LV, cathode-follower output on 6 grids)", v[len(pins)], "lv"),
                     ("PL_Y0a (HV, plate of a load gate on Y)", v[len(pins) + 1], "hv")]
        else:
            rows += [(f"{y} (HV, plate)", v[len(pins)], "hv"), (f"{y}_LV (after the divider, 6 grids)", v[len(pins) + 1], "lv")]
        labels = ["".join(map(str, s)) for s in c['seq']]
        labels[0] = "".join(c['pins']) + "\n" + labels[0]
        LP.wave_fig(dest(out, key, "tran.png"), f"{name}: KiCad testbench in ngspice, fanout 6", t, rows, labels=labels)
        res[key] = r
    return res


def LP_TMP(tmp):
    return tmp


def transfer(out, tmp):
    """Y against the HV net of one input (swept 30..160 V), the other inputs at levels that make it count"""
    sens = {"a1": {"A": (None, 1, 0), "B": (1, None, 0), "C": (0, 0, None)},
            "a22": {"A": (None, 1, 0, 0), "B": (1, None, 0, 0), "C": (0, 0, None, 1), "D": (0, 0, 1, None)},
            "n4": {"A": (None, 0, 0, 0), "B": (0, None, 0, 0), "C": (0, 0, None, 0), "D": (0, 0, 0, None)},
            "o4": {"A": (None, 0, 0, 0), "B": (0, None, 0, 0), "C": (0, 0, None, 0), "D": (0, 0, 0, None)}}
    th = {}
    for key, (name, _) in CELL.items():
        c = A.CELLS[key]; p = A.params(key)
        fig, ax = plt.subplots(figsize=(7, 4.2), constrained_layout=True)
        th[key] = {}
        for k, (pin, st) in enumerate(sens[key].items()):
            s = f"* {name} vtc\n.include {A.LIBS}/6Zh2B.sub\n.include {A.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\nVNB20 nb20 0 -20\n"
            ins = {}
            for q, b in zip(c['pins'], st):
                n = q.lower(); ins[q] = n
                s += f"VH{n} h{n} 0 {HV[b] if b is not None else 100}\nR1{n} h{n} {n} 470k\nR2{n} {n} nb 200k\n"
            s += A.cell_net(c, ins, "y", p)
            lv = c.get('out') == "LV"
            # an LV output: what it means on the next HV net, the plate of a load gate
            s += A.L.loads("y", p, 6, "y") if lv else f"R1y y yl 470k\nR2y yl nb 200k\n" + A.L.loads("yl", p, 6, "y")
            wave = os.path.join(tmp, f"vtc_{key}_{pin}.txt")
            s += f".control\ndc VH{pin.lower()} 30 160 0.5\nwrdata {wave} v({A.PLATE if lv else 'y'})\n.endc\n.end\n"
            fn = os.path.join(tmp, f"vtc_{key}_{pin}.cir"); open(fn, "w").write(s); LP.ngspice(fn)
            d = np.loadtxt(wave); x, yv = d[:, 0], d[:, 1]
            ax.plot(x, yv, lw=1.8, color=(LP.BLUE, LP.ORANGE, LP.GREEN, "#8a5cc2")[k], label=f"{pin}")
            i100 = np.argmin(abs(yv - 100)); th[key][pin] = x[i100]
            ax.text(x[-1] + 1, yv[-1], pin, fontsize=8, va="center")
        for yy, txt in ((150, "+150"), (92, "92: next stage sees 0"), (50, "+50")):
            LP.refline(ax, yy, txt, 162)
        ax.set_xlabel("HV net feeding the input, V"); ax.set_ylabel("load plate on Y, V" if c.get('out') == "LV" else "Y, V"); ax.set_xlim(30, 175); ax.set_ylim(0, 160)
        ax.set_title(f"{name}: static transfer, fanout 6 (other inputs at the levels that make the input count)", loc="left", fontsize=10)
        ax.legend(frameon=False, loc="lower left", fontsize=8)
        fig.savefig(dest(out, key, "vtc.png"), dpi=110); plt.close(fig)
    return th


def fanout(out):
    jobs = [(k, A.params(k), n) for k in CELL for n in GRIDS]
    with Pool(8) as pool:
        res = pool.map(A.run, jobs)
    for key, (name, _) in CELL.items():
        rows = [(n, m) for k, _, n, m in res if k == key]
        arcs = A.arcs(A.CELLS[key])
        lv = A.CELLS[key].get('out') == "LV"
        fig, ax = plt.subplots(figsize=(7, 4.2), constrained_layout=True)
        if lv:      # an LV output: plot the delay to the load plate (input -5 V -> load plate 100 V)
            arcs = [(k + "p", pin, di, do, t) for k, pin, di, do, t in arcs]
        for i, (k, pin, di, do, t) in enumerate(arcs):
            col = LP.BLUE if do == "fall" else LP.ORANGE
            ys = [m.get(k, np.nan) * 1e9 for n, m in rows]
            ax.plot(GRIDS, ys, color=col, lw=1.2, alpha=0.8, marker="o", ms=3)
            ax.text(GRIDS[-1] + 0.15, ys[-1], k, fontsize=7, va="center", color=col)
        ax.plot([], [], color=LP.BLUE, label="Y falls (tpHL)"); ax.plot([], [], color=LP.ORANGE, label="Y rises (tpLH)")
        ax.set_xlim(1, GRIDS[-1] + 2.2); ax.set_ylim(0, None); ax.set_xticks(GRIDS)
        ax.set_xlabel("grids on Y (fanout)"); ax.set_ylabel("ns, input −5 V → load plate 100 V" if lv else "ns, input −5 V → Y 100 V")
        ax.set_title(f"{name}: delay of every arc against fanout", loc="left", fontsize=10)
        ax.legend(frameon=False, loc="upper left", fontsize=8)
        fig.savefig(dest(out, key, "fanout.png"), dpi=110); plt.close(fig)
    return res


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
    with tempfile.TemporaryDirectory() as tmp:
        schematics(out, tmp)
        tb = waveforms(out, tmp)
        th = transfer(out, tmp)
    for k, r in tb.items():
        print(CELL[k][0], "KiCad tb:", A.fmt(k, "kicad tb", 6, r))
    for k, d in th.items():
        print(CELL[k][0], "Y = 100 V at HV input:", ", ".join(f"{p} {v:.1f} V" for p, v in d.items()))
    for r in fanout(out):
        print(A.fmt(*r))
    print("figures in", out or "sch/logic/<CELL>/img")
