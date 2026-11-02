#!/usr/bin/env python3
"""Redraw the 6Zh2B reference-sheet curves (doc/6zh2b_datasheet.md).

usage: tools/spice/datasheet_6zh2b_plots.py [OUT_DIR]        (default: doc/img)

Data: doc/data/6zh2b_datasheet.json (digitized from the scan, doc/digitizing_reference_sheets.md).
Model: sch/libs/6Zh2B.sub (tools/spice/fit_6zh2b.py) through ngrun.py.
Writes 6zh2b_ia_ua.png (Рис. 215), 6zh2b_ia_ug3.png (Рис. 216) and 6zh2b_model.png (sheet vs model).
"""
import json, os, subprocess, sys, tempfile
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = json.load(open(os.path.join(REPO, "doc", "data", "6zh2b_datasheet.json")))
MODEL = os.path.join(REPO, "sch", "libs", "6Zh2B.sub")

BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, MUTED, GRID, SURF = "#1f1f1e", "#6b6a64", "#e4e3dc", "#fcfcfb"
plt.rcParams.update({"figure.facecolor": SURF, "axes.facecolor": SURF, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "text.color": INK, "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True,
                     "grid.color": GRID, "grid.linewidth": 0.8})


def xy(pts):
    a = np.array(pts, dtype=float)
    return a[:, 0], a[:, 1]


def family(ax, key, color, ls, dx, dy):
    for ug, pts in DATA["plots"][key]["curves"].items():
        u, i = xy(pts)
        ax.plot(u, i, color=color, lw=2, ls=ls)
        ax.text(u[-1] + dx, i[-1] + dy, f"{ug} V", fontsize=8, color=color)


def legend(ax):
    ax.plot([], [], color=BLUE, lw=2, label="Ia, plate current")
    ax.plot([], [], color=ORANGE, lw=2, ls=(0, (5, 2)), label="Ig2, screen current")
    ax.legend(loc="upper right", fontsize=8, frameon=False)


def ia_ua(out):
    fig, ax = plt.subplots(figsize=(9, 5.4), constrained_layout=True)
    family(ax, "ia_ua", BLUE, "-", 1.5, 0.1)
    family(ax, "ic2_ua", ORANGE, (0, (5, 2)), 1.5, -0.35)
    ax.set_xlim(0, 205); ax.set_ylim(0, 14.5)
    ax.set_xticks(range(0, 191, 20)); ax.set_yticks(range(0, 15, 2))
    ax.set_xlabel("Ua, V"); ax.set_ylabel("Ia, Ig2, mA"); legend(ax)
    ax.set_title("Ia, Ig2 = f(Ua), Ug2 = 120 V, Ug3 = 0, Uh = 6.3 V; curves labelled with Ug1", loc="left", fontsize=10)
    fig.savefig(os.path.join(out, "6zh2b_ia_ua.png"), dpi=110); plt.close(fig)


def ia_ug3(out):
    fig, ax = plt.subplots(figsize=(8, 5.4), constrained_layout=True)
    family(ax, "ia_ug3", BLUE, "-", 0.15, 0.1)
    family(ax, "ic2_ug3", ORANGE, (0, (5, 2)), 0.15, -0.35)
    ax.set_xlim(-10, 10.5); ax.set_ylim(0, 13)
    ax.set_xticks(range(-10, 10, 2)); ax.set_yticks(range(0, 14, 2))
    ax.set_xlabel("Ug3, V"); ax.set_ylabel("Ia, Ig2, mA"); legend(ax)
    ax.set_title("Ia, Ig2 = f(Ug3), Ua = Ug2 = 120 V, Uh = 6.3 V; curves labelled with Ug1", loc="left", fontsize=10)
    fig.savefig(os.path.join(out, "6zh2b_ia_ug3.png"), dpi=110); plt.close(fig)


def ngspice_dc(tmp, sweep, fixed, start, stop, step):
    """DC sweep of the model with Ug2 = 120 V; fixed = (ua, ug1, ug3) with the swept one ignored.
    Returns x, Ia mA, Ig2 mA."""
    ua, ug1, ug3 = fixed
    data = os.path.join(tmp, "dc.txt"); deck = os.path.join(tmp, "dc.cir")
    open(deck, "w").write(f"""* model check
.include {MODEL}
VA a 0 {ua}
VG2 g2 0 120
VG3 g3 0 {ug3}
VG1 g1 0 {ug1}
X1 a g3 g2 0 g1 6Zh2B
.control
dc {sweep} {start} {stop} {step}
wrdata {data} i(VA) i(VG2)
.endc
.end
""")
    subprocess.run([sys.executable, os.path.join(HERE, "ngrun.py"), deck], capture_output=True, check=True)
    d = np.loadtxt(data)
    return d[:, 0], -d[:, 1] * 1e3, -d[:, 3] * 1e3


def model(out):
    with tempfile.TemporaryDirectory() as tmp:
        mu = {g: ngspice_dc(tmp, "VA", (0, g, 0), 0, 190, 1) for g in (0, -1, -2, -3, -4)}
        m3 = {g: ngspice_dc(tmp, "VG3", (120, g, 0), -10, 9, 0.05) for g in (-1, -2, -3)}
    fig, axs = plt.subplots(1, 2, figsize=(11, 4.6), constrained_layout=True)
    for ax, sheet, mod, xk in ((axs[0], ("ia_ua", "ic2_ua"), mu, "Ua"), (axs[1], ("ia_ug3", "ic2_ug3"), m3, "Ug3")):
        for g, (x, ia, ig2) in mod.items():
            for key, y, color in ((sheet[0], ia, BLUE), (sheet[1], ig2, ORANGE)):
                u, i = xy(DATA["plots"][key]["curves"][str(g)])
                ax.plot(u, i, color=color, lw=2)
                ax.plot(x, y, color=INK, lw=1.2, ls=(0, (4, 2)))
            ax.text(u[-1], i[-1] - 0.45, f"{g} V", fontsize=8, color=ORANGE)
        ax.set_xlabel(xk + ", V"); ax.set_ylabel("Ia, Ig2, mA")
    axs[0].set_xlim(0, 200); axs[0].set_ylim(0, 14.5)
    axs[1].set_xlim(-10, 10); axs[1].set_ylim(0, 13)
    axs[0].set_title("Ug2 = 120 V, Ug3 = 0; by Ug1", loc="left", fontsize=10)
    axs[1].set_title("Ua = Ug2 = 120 V; by Ug1", loc="left", fontsize=10)
    axs[0].plot([], [], color=BLUE, lw=2, label="Ia, sheet"); axs[0].plot([], [], color=ORANGE, lw=2, label="Ig2, sheet")
    axs[0].plot([], [], color=INK, lw=1.2, ls=(0, (4, 2)), label="model 6Zh2B.sub")
    axs[0].legend(frameon=False, fontsize=8, loc="upper right", bbox_to_anchor=(1.0, 0.93))
    fig.suptitle("Reference sheet (solid, Рис. 215 and 216) vs SPICE model (dashed)", x=0.01, ha="left", fontsize=11)
    fig.savefig(os.path.join(out, "6zh2b_model.png"), dpi=110); plt.close(fig)
    rows = []  # numeric comparison for the page
    for name, mod, key, g, x0 in (("Ia", mu, "ia_ua", 0, 50), ("Ig2", mu, "ic2_ua", 0, 50), ("Ia", mu, "ia_ua", -2, 120),
                                  ("Ia", mu, "ia_ua", -4, 120), ("Ia", m3, "ia_ug3", -1, -5), ("Ig2", m3, "ic2_ug3", -1, -5),
                                  ("Ia", m3, "ia_ug3", -1, 0), ("Ig2", m3, "ic2_ug3", -1, -9.9)):
        u, i = xy(DATA["plots"][key]["curves"][str(g)])
        x, ia, ig2 = mod[g]
        rows.append((name, key, g, x0, float(np.interp(x0, u, i)), float(np.interp(x0, x, ia if name == "Ia" else ig2))))
    return rows


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "doc", "img")
    ia_ua(out); ia_ug3(out)
    for name, key, g, x0, ds, md in model(out):
        print(f"{name:3s} {key:8s} Ug1 {g:2d} V at {x0:6.1f} V: sheet {ds:5.2f} mA, model {md:5.2f} mA ({(md - ds) / ds * 100:+.0f} %)")
    print("wrote", *(os.path.join(out, f) for f in ("6zh2b_ia_ua.png", "6zh2b_ia_ug3.png", "6zh2b_model.png")))
