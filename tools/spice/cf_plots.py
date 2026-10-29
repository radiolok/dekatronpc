#!/usr/bin/env python3
"""Build every figure of the BUF_N16 / OR2_N16 cell page (sch/logic/BUF_N16/README.md) from the sources in the repo.

usage: tools/spice/cf_plots.py [OUT_DIR]          (default: each figure into sch/logic/<CELL>/img)

Writes buf_n16_cell.png, or2_n16_cell.png, buf_n16_tb.png, or2_n16_tb.png (schematics exported from KiCad),
buf_n16_tran.png, or2_n16_tran.png (KiCad testbench waveforms), cf_n16_vtc.png (static transfer, cf_static.py)
and cf_n16_fanout.png (delay vs fanout, cf_sweep.py). Needs kicad-cli, rsvg-convert, matplotlib, Pillow and
KiCad's libngspice. Copied from not_plots.py; the chart style follows doc/cell_design_method.md §7.
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
import cf_sweep, cf_static  # noqa: E402

# ---- CELLS: what to plot -----------------------------------------------------------------------------
CELLS = {
    "BUF": dict(sch=os.path.join(REPO, "sch", "logic", "BUF_N16", "BUF_N16_tb.kicad_sch"), svg="BUF_N16_tb-DUT.svg",
                waves=[("A (LV, DUT grid A1)", "/A", "lv"), ("B (LV, DUT grid A2)", "/B", "lv"),
                       ("YA (LV, output Y1 on 10 grids)", "/YA", "out"), ("YB (LV, output Y2 on 10 grids)", "/YB", "out"),
                       ("PLA (HV, plate of a load gate on YA)", "/PLA", "hv")]),
    "OR2": dict(sch=os.path.join(REPO, "sch", "logic", "OR2_N16", "OR2_N16_tb.kicad_sch"), svg="OR2_N16_tb-DUT.svg",
                waves=[("A (LV, DUT grid A)", "/A", "lv"), ("B (LV, DUT grid B)", "/B", "lv"),
                       ("YA (LV, output Y on 10 grids)", "/YA", "out"),
                       ("PLA (HV, plate of a load gate on Y)", "/PLA", "hv")]),
}
CELL_CROP_MM = (34, 50, 270, 205)               # area of the cell drawing on its A4 page
IMG_CELL = {"buf_n16_cell.png": "BUF_N16", "buf_n16_tb.png": "BUF_N16", "buf_n16_tran.png": "BUF_N16",
            "cf_n16_vtc.png": "BUF_N16", "cf_n16_fanout.png": "BUF_N16",
            "or2_n16_cell.png": "OR2_N16", "or2_n16_tb.png": "OR2_N16", "or2_n16_tran.png": "OR2_N16"}

def dest(out, png):
    """Where a figure goes: OUT_DIR if given, else the img/ folder of the cell page that shows it."""
    d = out or os.path.join(REPO, "sch", "logic", IMG_CELL[png], "img")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, png)

GRIDS = (2, 4, 6, 8, 10)

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
def schematics(cell, c, out, tmp):
    svg = os.path.join(tmp, "svg_" + cell)
    os.makedirs(svg, exist_ok=True)
    subprocess.run(["kicad-cli", "sch", "export", "svg", "-e", "-o", svg, c["sch"]], check=True, capture_output=True)
    k = 8
    png = os.path.join(tmp, cell + "_cell.png")
    subprocess.run(["rsvg-convert", "-w", str(297 * k), "-b", "white", os.path.join(svg, c["svg"]), "-o", png], check=True)
    Image.open(png).convert("RGB").crop(tuple(int(v * k) for v in CELL_CROP_MM)).save(
        dest(out, cell.lower() + "_n16_cell.png"))
    # testbench: crop to the coloured pixels inside the frame (skip the page border and title block)
    root = os.path.splitext(os.path.basename(c["sch"]))[0] + ".svg"
    png = os.path.join(tmp, cell + "_tb.png")
    subprocess.run(["rsvg-convert", "-w", "3360", "-b", "white", os.path.join(svg, root), "-o", png], check=True)
    im = Image.open(png).convert("RGB")
    w, h = im.size
    a = np.asarray(im).astype(int)[int(h * 0.03):int(h * 0.78), int(w * 0.02):int(w * 0.97)]
    ys, xs = np.nonzero(a.max(axis=2) - a.min(axis=2) > 60)
    m = 30
    x0, y0 = int(w * 0.02), int(h * 0.03)
    im.crop((x0 + xs.min() - m, y0 + ys.min() - m, x0 + xs.max() + m, y0 + ys.max() + m)).save(
        dest(out, cell.lower() + "_n16_tb.png"))


# ---- KiCad testbench waveforms ------------------------------------------------------------------------
def waveforms(cell, c, out, tmp):
    prj = os.path.dirname(c["sch"])
    name = os.path.splitext(os.path.basename(c["sch"]))[0]
    cir = os.path.join(tmp, name + ".cir")
    subprocess.run(["kicad-cli", "sch", "export", "netlist", "--format", "spice", "-o", cir, c["sch"]],
                   check=True, capture_output=True)
    txt = open(cir).read().replace('.include "/../', '.include "%s/../' % prj)
    wave = os.path.join(tmp, cell + "_wave.txt")
    vecs = " ".join("v(%s)" % n for _, n, _ in c["waves"])
    txt = re.sub(r"^\.end\s*$", ".control\nrun\nwrdata %s %s\n.endc\n.end\n" % (wave, vecs), txt, flags=re.M)
    open(cir, "w").write(txt)
    res = meas(ngspice(cir))
    d = np.loadtxt(wave)
    t = d[:, 0] * 1e6
    tend = t[-1]
    W = c["waves"]
    fig, axs = plt.subplots(len(W), 1, sharex=True, figsize=(9, 2 * len(W)), constrained_layout=True)
    for i, (ax, (title, _, fam)) in enumerate(zip(axs, W)):
        ax.plot(t, d[:, 1 + 2 * i], color=BLUE, lw=2)
        ax.set_title(title, loc="left", fontsize=10)
        ax.set_ylabel("V")
        if fam == "hv":
            refline(ax, 150, "1 = +150", tend * 1.005); refline(ax, 50, "0 = +50", tend * 1.005)
            refline(ax, 92, "VIL 92", tend * 1.005); ax.set_ylim(20, 165)
        elif fam == "out":
            refline(ax, 0, "clamp ≈ 0", tend * 1.005); refline(ax, -7.6, "VIL −7.6", tend * 1.005)
            refline(ax, -20, "0 = −20", tend * 1.005); refline(ax, -50, "Ug limit", tend * 1.005); ax.set_ylim(-55, 15)
        else:
            refline(ax, 10, "1 = +10", tend * 1.005); refline(ax, -20, "0 = −20", tend * 1.005)
            refline(ax, -50, "Ug limit", tend * 1.005); ax.set_ylim(-55, 25)
    sa, sb = cf_sweep.SEQ[cell]
    for k, (a, b) in enumerate(zip(sa, sb)):
        axs[0].text(2 * k + 1, -44, ("AB=" if k == 0 else "") + f"{a}{b}", ha="center", va="top", fontsize=8, color=MUTED)
    axs[-1].set_xlabel("t, µs"); axs[-1].set_xlim(0, tend)
    fig.suptitle(f"{cell}_N16: KiCad testbench in ngspice, 10 grids on each output", x=0.01, ha="left", fontsize=12)
    fig.savefig(dest(out, cell.lower() + "_n16_tran.png"), dpi=110)
    plt.close(fig)
    return res


# ---- static transfer ----------------------------------------------------------------------------------
def transfer(out):
    rows = {n: cf_static.dc(n) for n in (2, 10)}
    th = cf_static.thresholds(rows[10])
    fig, axs = plt.subplots(1, 2, figsize=(10, 3.8), constrained_layout=True)
    for ax, col, title, unit in ((axs[0], 1, "Y (LV output) vs the HV net feeding the input", "Y, V"),
                                 (axs[1], 2, "Plate of a load gate on Y", "V")):
        for n, color in ((2, ORANGE), (10, BLUE)):
            r = np.array(rows[n])
            ax.plot(r[:, 0], r[:, col], color=color, lw=2, label=f"{n} grids")
        ax.set_title(title, loc="left", fontsize=10)
        ax.set_xlabel("HV input net (driver plate), V"); ax.set_ylabel(unit)
        for x, txt in ((55, "HV 0\n(NOT)"), (146.9, "HV 1\n(NOT)")):
            ax.axvline(x, color=MUTED, ls=(0, (1, 2)), lw=1)
        ax.legend(frameon=False, loc="upper left")
    axs[0].axhline(-7.6, color=MUTED, ls=(0, (4, 3)), lw=1); axs[0].text(32, -6.8, "load VIL −7.6 V", fontsize=8, color=MUTED)
    axs[0].text(57, -22, "HV 0\n55 V", fontsize=8, color=MUTED); axs[0].text(129, -22, "HV 1\n147 V", fontsize=8, color=MUTED)
    axs[1].axhline(92, color=MUTED, ls=(0, (4, 3)), lw=1); axs[1].text(32, 95, "next VIL 92 V", fontsize=8, color=MUTED)
    axs[1].axvline(th[2], color=MUTED, ls=(0, (4, 3)), lw=1)
    axs[1].text(th[2] - 2, 60, "plate < 92 V\nfrom %.1f V" % th[2], fontsize=8, color=MUTED, ha="right")
    fig.savefig(dest(out, "cf_n16_vtc.png"), dpi=110)
    plt.close(fig)
    return th


# ---- delay vs fanout ----------------------------------------------------------------------------------
def fanout(out):
    jobs = [(c, "cell", dict(cf_sweep.DEFAULT), n) for c in ("BUF", "OR2") for n in GRIDS]
    with Pool(min(8, os.cpu_count() or 1)) as pool:
        rows = pool.map(cf_sweep.run, jobs)
    fig, axs = plt.subplots(1, 2, figsize=(10, 3.8), constrained_layout=True, sharey=True)
    for ax, cell in zip(axs, ("BUF", "OR2")):
        rr = [r for r in rows if r[0] == cell]
        fo = [n for _, _, n, _ in rr]
        mx = lambda m, pre: max(v for k, v in m.items() if k.startswith(pre)) * 1e9
        up = [mx(m, "tqlh") for *_, m in rr]      # Y rises -> load plate falls
        dn = [mx(m, "tqhl") for *_, m in rr]      # Y falls -> load plate rises
        ax.plot(fo, dn, color=ORANGE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="Y falls (load plate rises)")
        ax.plot(fo, up, color=BLUE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="Y rises (load plate falls)")
        ax.text(fo[-1] + 0.2, dn[-1], "%.0f ns" % dn[-1], va="center", fontsize=9)
        ax.text(fo[-1] + 0.2, up[-1], "%.0f ns" % up[-1], va="center", fontsize=9)
        ax.set_xlim(1, fo[-1] + 1.8); ax.set_xticks(fo)
        ax.set_xlabel("grids on Y (fanout)")
        ax.set_title(f"{cell}_N16: input grid −5 V → load plate 100 V", loc="left", fontsize=10)
        ax.legend(frameon=False, loc="upper left")
    axs[0].set_ylabel("ns"); axs[0].set_ylim(0, 300)
    fig.savefig(dest(out, "cf_n16_fanout.png"), dpi=110)
    plt.close(fig)
    return rows


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
    with tempfile.TemporaryDirectory() as tmp:
        for cell, c in CELLS.items():
            schematics(cell, c, out, tmp)
            tb = waveforms(cell, c, out, tmp)
            print(f"{cell} testbench .meas:", ", ".join("%s=%.4g" % kv for kv in sorted(tb.items())))
        th = transfer(out)
        rows = fanout(out)
    print("transfer (10 grids): load plate < 140 V at HV %.1f V, 100 V at %.1f V, < 92 V at %.1f V" % th)
    for r in rows:
        print(cf_sweep.fmt(*r))
    print("figures in", out or "sch/logic/<CELL>/img")
