#!/usr/bin/env python3
"""Build every figure of the NOR2_N16 cell page (sch/logic/NOR2_N16/README.md) from the sources in the repo.

usage: tools/spice/nor2_plots.py [OUT_DIR]          (default: sch/logic/NOR2_N16/img)

Writes nor2_n16_cell.png, nor2_n16_tb.png (schematics exported from KiCad), nor2_n16_tran.png (KiCad testbench
waveforms), nor2_n16_vtc.png (static transfer) and nor2_n16_fanout.png (delay vs fanout, nor2_sweep.py).
Needs kicad-cli, rsvg-convert, matplotlib, Pillow and KiCad's libngspice. Copy it for a new cell and change
the CELL block below; the chart style follows doc/cell_design_method.md §7.
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
import nor2_sweep  # noqa: E402

# ---- CELL: what to plot ------------------------------------------------------------------------------
CELL_DIR = os.path.join(REPO, "sch", "logic", "NOR2_N16")
CELL_SCH = os.path.join(CELL_DIR, "NOR2_N16_tb.kicad_sch")
CELL_SHEET_SVG = "NOR2_N16_tb-DUT.svg"          # the DUT page of the testbench export = the cell sheet
CELL_CROP_MM = (70, 50, 190, 145)               # area of the cell drawing on its A4 page
PARAMS = dict(R1="470k", R2="200k", C1g=3.9, Ra="10k")
GRIDS = (2, 4, 6, 8, 10)
WAVES = [("IN_A (LV, DUT grid A)", "/IN_A", "lv"), ("IN_B (LV, DUT grid B)", "/IN_B", "lv"),
         ("OUT (HV, DUT plate)", "/OUT", "hv"), ("OUT_LV (after divider, 10 grids)", "/OUT_LV", "lv")]
STATES = ["AB=00", "10", "01", "11", "00"]       # 2 us each
VTC_DECK = """* VTC: LV input A swept (B at -20 V), HV out with one divider to 10 grids
.include {model}
VCC vcc 0 150
VNB nb 0 -50
VA a 0 -20
VB b 0 -20
X1 p a 0 p b 0 6N16B
RA vcc p {Ra}
R1 p yl {R1}
R2 yl nb {R2}
XL1 pl yl 0 pl yl 0 6N16B
XL2 pl yl 0 pl yl 0 6N16B
XL3 pl yl 0 pl yl 0 6N16B
XL4 pl yl 0 pl yl 0 6N16B
XL5 pl yl 0 pl yl 0 6N16B
RAL vcc pl 2k
.control
dc VA -20 2 0.05
wrdata {out} v(p) v(yl)
let g = deriv(v(p))
meas dc vth when v(p)=100
meas dc vil when g=-1 cross=1
.endc
.end
"""

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
    Image.open(png).convert("RGB").crop(tuple(int(v * k) for v in CELL_CROP_MM)).save(os.path.join(out, "nor2_n16_cell.png"))
    # testbench: crop to the coloured pixels (wires, symbols, text), which skips the page border
    root = os.path.splitext(os.path.basename(CELL_SCH))[0] + ".svg"
    png = os.path.join(tmp, "tb.png")
    subprocess.run(["rsvg-convert", "-w", "2520", "-b", "white", os.path.join(svg, root), "-o", png], check=True)
    im = Image.open(png).convert("RGB")
    a = np.asarray(im).astype(int)
    ys, xs = np.nonzero(a.max(axis=2) - a.min(axis=2) > 60)
    m = 30
    im.crop((xs.min() - m, ys.min() - m, xs.max() + m, ys.max() + m)).save(os.path.join(out, "nor2_n16_tb.png"))


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
            refline(ax, -50, "Ug limit", tend * 1.005); ax.set_ylim(-55, 15)
    for k, s in enumerate(STATES):
        axs[0].text(2 * k + 1, -44, s, ha="center", va="top", fontsize=8, color=MUTED)
    axs[-1].set_xlabel("t, µs"); axs[-1].set_xlim(0, tend)
    fig.suptitle("NOR2_N16: KiCad testbench in ngspice, fanout 10", x=0.01, ha="left", fontsize=12)
    fig.savefig(os.path.join(out, "nor2_n16_tran.png"), dpi=110)
    plt.close(fig)
    return res


# ---- static transfer ----------------------------------------------------------------------------------
def transfer(out, tmp):
    data = os.path.join(tmp, "vtc.txt")
    deck = os.path.join(tmp, "vtc.cir")
    open(deck, "w").write(VTC_DECK.format(model=os.path.join(REPO, "sch", "libs", "6N16B.sub"), out=data, **PARAMS))
    res = meas(ngspice(deck))
    v = np.loadtxt(data)
    fig, axs = plt.subplots(1, 2, figsize=(9, 3.6), constrained_layout=True)
    axs[0].plot(v[:, 0], v[:, 1], color=BLUE, lw=2)
    axs[0].set_title("HV output Y vs LV input (other input at −20 V)", loc="left", fontsize=10)
    axs[0].set_xlabel("LV input, V"); axs[0].set_ylabel("Y, V")
    vth, vil = res["vth"], res["vil"]
    axs[0].axvline(vth, color=MUTED, ls=(0, (4, 3)), lw=1)
    axs[0].text(vth + 0.2, 135, "Y = 100 V\nat %.1f V" % vth, fontsize=8, color=MUTED)
    axs[0].axvline(vil, color=MUTED, ls=(0, (1, 2)), lw=1)
    axs[0].text(vil - 4.7, 70, "VIL %.1f V\n(slope −1)" % vil, fontsize=8, color=MUTED)
    axs[1].plot(v[:, 0], v[:, 3], color=BLUE, lw=2)
    axs[1].set_title("LV net after the divider (10 grids)", loc="left", fontsize=10)
    axs[1].set_xlabel("LV input, V"); axs[1].set_ylabel("V")
    fig.savefig(os.path.join(out, "nor2_n16_vtc.png"), dpi=110)
    plt.close(fig)
    return res


# ---- delay vs fanout ----------------------------------------------------------------------------------
def fanout(out):
    with Pool(min(8, os.cpu_count() or 1)) as pool:
        rows = pool.map(nor2_sweep.run, [("cell", PARAMS, n) for n in GRIDS])
    fo = [n for _, n, _ in rows]
    hl = [m["tphl"] * 1e9 for _, _, m in rows]
    lh = [m["tplh"] * 1e9 for _, _, m in rows]
    fig, ax = plt.subplots(figsize=(6.5, 3.6), constrained_layout=True)
    ax.plot(fo, lh, color=ORANGE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="tpLH (Y rises)")
    ax.plot(fo, hl, color=BLUE, lw=2, marker="o", ms=8, mec=SURF, mew=2, label="tpHL (Y falls)")
    ax.text(fo[-1] + 0.2, lh[-1], "%.0f ns" % lh[-1], va="center", fontsize=9)
    ax.text(fo[-1] + 0.2, hl[-1], "%.0f ns" % hl[-1], va="center", fontsize=9)
    ax.set_xlim(1, fo[-1] + 1.5); ax.set_ylim(0, max(lh) * 1.1); ax.set_xticks(fo)
    ax.set_xlabel("grids on the output LV net (fanout)"); ax.set_ylabel("ns")
    ax.set_title("Gate delay vs fanout (LV −5 V → HV 100 V)", loc="left", fontsize=10)
    ax.legend(frameon=False, loc="upper left")
    fig.savefig(os.path.join(out, "nor2_n16_fanout.png"), dpi=110)
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
    print("transfer: Y=100 V at %.2f V, VIL %.2f V" % (vtc["vth"], vtc["vil"]))
    for r in rows:
        print(nor2_sweep.fmt(*r))
    print("figures in", out)
