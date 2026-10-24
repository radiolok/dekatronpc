#!/usr/bin/env python3
"""Redraw the 6Zh2B reference-sheet curves (doc/6zh2b_datasheet.md).

usage: tools/spice/datasheet_6zh2b_plots.py [OUT_DIR]        (default: doc/img)

Data: doc/data/6zh2b_datasheet.json (digitized from the scan, doc/digitizing_reference_sheets.md).
Writes 6zh2b_ia_ua.png (Рис. 215) and 6zh2b_ia_ug3.png (Рис. 216).
"""
import json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = json.load(open(os.path.join(REPO, "doc", "data", "6zh2b_datasheet.json")))

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


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "doc", "img")
    ia_ua(out); ia_ug3(out)
    print("wrote", os.path.join(out, "6zh2b_ia_ua.png"), os.path.join(out, "6zh2b_ia_ug3.png"))
