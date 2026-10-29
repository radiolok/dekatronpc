#!/usr/bin/env python3
"""Build every figure of the NAND2_J2 cell page (sch/logic/NAND2_J2/README.md) from the sources in the repo.

usage: tools/spice/nand2_plots.py [OUT_DIR]          (default: sch/logic/NAND2_J2/img)

Writes nand2_j2_cell.png, nand2_j2_tb.png (schematics exported from KiCad), nand2_j2_tran.png (KiCad testbench
waveforms), nand2_j2_vtc.png (static transfer, nand2_static.py) and nand2_j2_fanout.png (delay vs fanout,
nand2_sweep.py). Copied from nor2_plots.py; needs kicad-cli, rsvg-convert, matplotlib, Pillow and libngspice.
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import nand2_sweep, nand2_static  # noqa: E402

# ---- CELL: what to plot ------------------------------------------------------------------------------
CELL_DIR = os.path.join(REPO, "sch", "logic", "NAND2_J2")
CELL_SCH = os.path.join(CELL_DIR, "NAND2_J2_tb.kicad_sch")
CELL_SHEET_SVG = "NAND2_J2_tb-DUT.svg"          # the DUT page of the testbench export = the cell sheet
CELL_CROP_MM = (60, 52, 172, 142)               # area of the cell drawing on its A4 page
PARAMS = dict(R1="470k", R2="200k", C1g=3.9, C1g3=6.8, Cb=15, Ra="15k", Rg2="15k")
GRIDS = (2, 4, 6, 8, 10)
WAVES = [("IN_A (LV, DUT g1)", "/IN_A", "lv"), ("IN_B (LV, DUT g3)", "/IN_B", "lv"),
         ("OUT (HV, DUT plate)", "/OUT", "hv"), ("OUT_LV (after divider, 10 grids)", "/OUT_LV", "lv")]
STATES = ["AB=00", "10", "11", "01", "01", "11", "10", "00"]       # 2 us each, nand2_sweep.KICAD_A/B

# ---- style (light surface, one hue per panel, muted reference lines) ---------------------------------
BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, MUTED, GRID, SURF = "#1f1f1e", "#6b6a64", "#e4e3dc", "#fcfcfb"
plt.rcParams.update({"figure.facecolor": SURF, "axes.facecolor": SURF, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "text.color": INK, "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True,
                     "grid.color": GRID, "grid.linewidth": 0.8})


def ngspice(deck_path):
    return subprocess.run([sys.executable, os.path.join(HERE, "ngrun.py"), deck_path],
                          capture_output=True, text=True, check=True).stdout


def meas(text):
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", text, re.M)}


def refline(ax, y, txt, x):
    ax.axhline(y, color=MUTED, ls=(0, (4, 3)), lw=1)
    ax.text(x, y, txt, va="center", ha="left", fontsize=8, color=MUTED)


# ---- schematics ---------------------------------------------------------------------------------------
def schematics(out, tmp):
    svg = os.path.join(tmp, "svg")
    os.makedirs(svg, exist_ok=True)
    subprocess.run(["kicad-cli", "sch", "export", "svg", "-e", "-o", svg, CELL_SCH], check=True, capture_output=True)
    # cell: fixed crop of its A4 page
    k = 8
    png = os.path.join(tmp, "cell.png")
    subprocess.run(["rsvg-convert", "-w", str(297 * k), "-b", "white", os.path.join(svg, CELL_SHEET_SVG), "-o", png], check=True)
    Image.open(png).convert("RGB").crop(tuple(int(v * k) for v in CELL_CROP_MM)).save(os.path.join(out, "nand2_j2_cell.png"))
    # testbench: crop to the coloured pixels (wires, symbols, text), which skips the page border
    root = os.path.splitext(os.path.basename(CELL_SCH))[0] + ".svg"
    png = os.path.join(tmp, "tb.png")
    subprocess.run(["rsvg-convert", "-w", "2520", "-b", "white", os.path.join(svg, root), "-o", png], check=True)
    im = Image.open(png).convert("RGB")
    a = np.asarray(im).astype(int)
    ys, xs = np.nonzero(a.max(axis=2) - a.min(axis=2) > 60)
    m = 30
    im.crop((xs.min() - m, ys.min() - m, xs.max() + m, ys.max() + m)).save(os.path.join(out, "nand2_j2_tb.png"))


# ---- KiCad testbench waveforms ------------------------------------------------------------------------
def waveforms(out, tmp):
    prj = os.path.dirname(CELL_SCH)
    name = os.path.splitext(os.path.basename(CELL_SCH))[0]
    cir = os.path.join(tmp, name + ".cir")
    subprocess.run(["kicad-cli", "sch", "export", "netlist", "--format", "spice", "-o", cir, CELL_SCH],
                   check=True, capture_output=True)
    txt = open(cir).read().replace('.include "/../', '.include "%s/../' % prj)
    wave = os.path.join(tmp, "wave.txt")
    vecs = " ".join("v(%s)" % n for _, n, _ in WAVES)
    txt = re.sub(r"^\.end\s*$", ".control\nrun\nwrdata %s %s\n.endc\n.end\n" % (wave, vecs), txt, flags=re.M)
    open(cir, "w").write(txt)
    res = meas(ngspice(cir))
    d = np.loadtxt(wave)
    t = d[:, 0] * 1e6
    tend = t[-1]
    fig, axs = plt.subplots(len(WAVES), 1, sharex=True, figsize=(9, 2 * len(WAVES)), constrained_layout=True)
    for i, (ax, (title, _, fam)) in enumerate(zip(axs, WAVES)):
        ax.plot(t, d[:, 1 + 2 * i], color=BLUE, lw=2)
        ax.set_title(title, loc="left", fontsize=10)
        ax.set_ylabel("V")
        if fam == "hv":
            refline(ax, 150, "1 = +150", tend * 1.005); refline(ax, 50, "0 = +50", tend * 1.005); ax.set_ylim(20, 165)
        else:
            refline(ax, 10, "1 = +10", tend * 1.005); refline(ax, -20, "0 = −20", tend * 1.005)
            refline(ax, -50, "Ug1 limit", tend * 1.005); ax.set_ylim(-55, 15)
    for k, s in enumerate(STATES):
        axs[0].text(2 * k + 1, -44, s, ha="center", va="top", fontsize=8, color=MUTED)
    axs[-1].set_xlabel("t, µs"); axs[-1].set_xlim(0, tend)
    fig.suptitle("NAND2_J2: KiCad testbench in ngspice, fanout 10", x=0.01, ha="left", fontsize=12)
    fig.savefig(os.path.join(out, "nand2_j2_tran.png"), dpi=110)
    plt.close(fig)
    return res


# ---- static transfer ----------------------------------------------------------------------------------
def transfer(out, tmp):
    fig, ax = plt.subplots(figsize=(7, 3.8), constrained_layout=True)
    res = {}
    for which, color, dy in (("A", BLUE, 5), ("B", ORANGE, -4)):
        hv, lv, y = nand2_static.transfer(which)
        t = nand2_static.thresholds(hv, lv, y)
        res[which] = t
        ax.plot(lv, y, color=color, lw=2, label=f"input {which} (g{'1' if which == 'A' else '3'}), other input high")
        ax.text(lv[-1] + 0.3, y[-1] + dy, which, color=color, fontsize=9, va="center")
        ax.plot([t["VIL_lv"]], [np.interp(t["VIL_lv"], lv, y)], "o", color=color, ms=6, mec=SURF, mew=1.5)
    ax.axhline(100, color=MUTED, ls=(0, (4, 3)), lw=1); ax.text(-20.5, 102, "Y = 100 V", fontsize=8, color=MUTED)
    ax.set_xlabel("LV input (after the divider), V"); ax.set_ylabel("Y, V")
    ax.set_title("HV output Y vs LV input, fanout 10; dots: VIL (slope −1)", loc="left", fontsize=10)
    ax.legend(frameon=False, loc="lower left", fontsize=8)
    fig.savefig(os.path.join(out, "nand2_j2_vtc.png"), dpi=110)
    plt.close(fig)
    return res


# ---- delay vs fanout ----------------------------------------------------------------------------------
def fanout(out):
    with Pool(min(8, os.cpu_count() or 1)) as pool:
        rows = pool.map(nand2_sweep.run, [("cell", PARAMS, n) for n in GRIDS])
    fo = [n for _, n, _ in rows]
    fig, axs = plt.subplots(1, 2, figsize=(10, 3.8), sharey=True, constrained_layout=True)
    top = max(max(m[k] for k in ("tphl_a", "tphl_b", "tplh_a", "tplh_b")) for _, _, m in rows) * 1e9 * 1.12
    for ax, inp, g in ((axs[0], "a", "A (g1)"), (axs[1], "b", "B (g3)")):
        lh = [m["tplh_" + inp] * 1e9 for _, _, m in rows]
        hl = [m["tphl_" + inp] * 1e9 for _, _, m in rows]
        ax.plot(fo, lh, color=ORANGE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="tpLH (Y rises)")
        ax.plot(fo, hl, color=BLUE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="tpHL (Y falls)")
        ax.text(fo[-1] + 0.2, lh[-1], "%.0f ns" % lh[-1], va="center", fontsize=9)
        ax.text(fo[-1] + 0.2, hl[-1], "%.0f ns" % hl[-1], va="center", fontsize=9)
        ax.set_xlim(1, fo[-1] + 1.8); ax.set_ylim(0, top); ax.set_xticks(fo)
        ax.set_xlabel("grids on the output LV net (fanout)")
        ax.set_title("Input " + g + ", the other input high", loc="left", fontsize=10)
    axs[0].set_ylabel("ns (LV −5 V → HV 100 V)")
    axs[0].legend(frameon=False, loc="upper left")
    fig.savefig(os.path.join(out, "nand2_j2_fanout.png"), dpi=110)
    plt.close(fig)
    return rows


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(CELL_DIR, "img"))
    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        schematics(out, tmp)
        tb = waveforms(out, tmp)
        vtc = transfer(out, tmp)
        rows = fanout(out)
    print("testbench .meas:", ", ".join("%s=%.4g" % kv for kv in sorted(tb.items())))
    for k, t in vtc.items():
        print("transfer %s: VIL %.1f V (%.0f V HV), Y = 100 V at %.1f V (%.0f V HV)" % (k, t["VIL_lv"], t["VIL_hv"], t["SW_lv"], t["SW_hv"]))
    for r in rows:
        print(nand2_sweep.fmt(*r))
    print("figures in", out)
