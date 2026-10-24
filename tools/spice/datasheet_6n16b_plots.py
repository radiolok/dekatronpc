#!/usr/bin/env python3
"""Redraw the 6N16B reference-sheet curves and compare them with the SPICE model (doc/6n16b_datasheet.md).

usage: tools/spice/datasheet_6n16b_plots.py [OUT_DIR]        (default: doc/img)

Data: doc/data/6n16b_datasheet.json (digitized from the scan). Model: sch/libs/6N16B.sub through ngrun.py.
Writes 6n16b_ia_ua.png, 6n16b_ia_ug.png, 6n16b_s_mu_ri.png, 6n16b_pulse.png, 6n16b_model.png.
"""
import json, os, subprocess, sys, tempfile
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = json.load(open(os.path.join(REPO, "doc", "data", "6n16b_datasheet.json")))
MODEL = os.path.join(REPO, "sch", "libs", "6N16B.sub")

BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, MUTED, GRID, SURF = "#1f1f1e", "#6b6a64", "#e4e3dc", "#fcfcfb"
plt.rcParams.update({"figure.facecolor": SURF, "axes.facecolor": SURF, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "text.color": INK, "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True,
                     "grid.color": GRID, "grid.linewidth": 0.8})


def xy(pts):
    a = np.array(pts, dtype=float)
    return a[:, 0], a[:, 1]


def title(ax, text):
    ax.set_title(text, loc="left", fontsize=10)


def ia_ua(out):
    fig, ax = plt.subplots(figsize=(9, 5.4), constrained_layout=True)
    for ug, pts in DATA["ia_ua"]["curves"].items():
        u, i = xy(pts)
        ax.plot(u, i, color=BLUE, lw=2)
        ax.text(u[-1] + 2, i[-1] + 0.15, f"{ug} V", fontsize=8, color=INK)
    ua = np.linspace(55, 240, 200)
    ax.plot(ua, DATA["ia_ua"]["pa_max_W"] * 1e3 / ua, color=MUTED, lw=1.2, ls=(0, (6, 2, 1, 2)))
    ax.text(150, 900 / 150 + 0.4, "Pa max 0.9 W", fontsize=8, color=MUTED, rotation=-14)
    ax.set_xlim(0, 245); ax.set_ylim(0, 16)
    ax.set_xticks(range(0, 241, 20)); ax.set_yticks(range(0, 17, 2))
    ax.set_xlabel("Ua, V"); ax.set_ylabel("Ia, mA")
    title(ax, "Ia = f(Ua) per triode, Uh = 6.3 V; curves labelled with Ug")
    fig.savefig(os.path.join(out, "6n16b_ia_ua.png"), dpi=110); plt.close(fig)


def ia_ug(out):
    fig, ax = plt.subplots(figsize=(6.5, 5.4), constrained_layout=True)
    for ua, pts in DATA["ia_ug"]["curves"].items():
        u, i = xy(pts)
        ax.plot(u, i, color=BLUE, lw=2)
        ax.text(u[-1] - 0.05, i[-1] + 0.2, f"Ua = {ua} V" if ua == "150" else f"{ua} V", fontsize=8, ha="right")
    ax.set_xlim(-8, 0); ax.set_ylim(0, 12.5)
    ax.set_xlabel("Ug, V"); ax.set_ylabel("Ia, mA")
    title(ax, "Ia = f(Ug) per triode, Uh = 6.3 V")
    fig.savefig(os.path.join(out, "6n16b_ia_ug.png"), dpi=110); plt.close(fig)


def s_mu_ri(out):
    d = DATA["s_mu_ri"]
    fig, axs = plt.subplots(1, 3, figsize=(10, 3.4), constrained_layout=True)
    for ax, key, lab, lim in ((axs[0], "S", "S, mA/V", (0, 7)), (axs[1], "mu", "μ", (10, 26)), (axs[2], "Ri", "Ri, kΩ", (0, 14))):
        x, y = xy(d[key]); ax.plot(x, y, color=BLUE, lw=2)
        ax.set_xlim(0, 10); ax.set_ylim(*lim); ax.set_xlabel("Ia, mA"); title(ax, lab)
    axs[0].axvline(6.3, color=MUTED, ls=(0, (4, 3)), lw=1)
    axs[0].text(6.45, 0.6, "nominal\n6.3 mA", fontsize=8, color=MUTED)
    fig.suptitle("S, μ, Ri = f(Ia) per triode, Ua = 100 V, Uh = 6.3 V", x=0.01, ha="left", fontsize=11)
    fig.savefig(os.path.join(out, "6n16b_s_mu_ri.png"), dpi=110); plt.close(fig)


def pulse(out):
    p = DATA["pulse"]
    fig, axs = plt.subplots(1, 2, figsize=(10, 4.2), constrained_layout=True, sharey=True)
    for ax, key, name in ((axs[0], "Ia_imp", "Ia imp, plate pulse current"), (axs[1], "Ig_imp", "Ig imp, grid pulse current")):
        labels = []
        for ug, pts in p[key].items():
            u, i = xy(pts); ax.plot(u, i, color=BLUE, lw=2)
            labels.append([i[-1], u[-1], f"{ug} V"])
        labels.sort()                                   # keep end labels at least 0.07 A apart
        for k in range(1, len(labels)):
            labels[k][0] = max(labels[k][0], labels[k - 1][0] + 0.07)
        for y, x, s in labels:
            ax.text(x + 5, y, s, fontsize=8, va="center")
        ax.set_xlim(0, 560); ax.set_ylim(0, 2.1); ax.set_xlabel("Ua, V"); title(ax, name + ", by Ug imp")
    axs[0].set_ylabel("A")
    fig.suptitle("Pulse mode per triode: f imp = 1 kHz, τ = 2 µs, Uh = 6.3 V", x=0.01, ha="left", fontsize=11)
    fig.savefig(os.path.join(out, "6n16b_pulse.png"), dpi=110); plt.close(fig)


def ngspice_dc(tmp, sweep, fixed_name, fixed_vals, start, stop, step):
    """DC sweep of one triode of the model; returns {fixed: (x, ia_mA)}"""
    res = {}
    for v in fixed_vals:
        data = os.path.join(tmp, f"dc_{fixed_name}_{v}.txt")
        va, vg = (("0", str(v)) if sweep == "VA" else (str(v), "0"))
        deck = os.path.join(tmp, "dc.cir")
        open(deck, "w").write(f"""* model check
.include {MODEL}
VA a 0 {va}
VG g 0 {vg}
X1 a g 0 a g 0 6N16B
.control
dc {sweep} {start} {stop} {step}
wrdata {data} -i(VA)
.endc
.end
""")
        subprocess.run([sys.executable, os.path.join(HERE, "ngrun.py"), deck], capture_output=True, check=True)
        d = np.loadtxt(data)
        res[v] = (d[:, 0], d[:, 1] / 2 * 1e3)       # both triodes in parallel -> per triode, mA
    return res


def model(out):
    with tempfile.TemporaryDirectory() as tmp:
        mu = ngspice_dc(tmp, "VA", "ug", [0, -2, -4, -6, -8], 0, 240, 1)
        mg = ngspice_dc(tmp, "VG", "ua", [80, 100, 120, 150], -8, 0, 0.02)
    fig, axs = plt.subplots(1, 2, figsize=(10, 4.4), constrained_layout=True)
    ax = axs[0]
    for ug in ["0", "-2", "-4", "-6", "-8"]:
        u, i = xy(DATA["ia_ua"]["curves"][ug])
        ax.plot(u, i, color=BLUE, lw=2, label="reference sheet" if ug == "0" else None)
        x, y = mu[int(ug)]; m = x <= u[-1] + 5
        ax.plot(x[m], y[m], color=ORANGE, lw=2, ls=(0, (5, 3)), label="model 6N16B.sub" if ug == "0" else None)
        ax.text(u[-1] + 3, i[-1], f"{ug} V", fontsize=8, va="center")
    ax.set_xlim(0, 250); ax.set_ylim(0, 14); ax.set_xlabel("Ua, V"); ax.set_ylabel("Ia, mA")
    title(ax, "Ia = f(Ua), Ug = 0 … −8 V"); ax.legend(frameon=False, loc="upper left", bbox_to_anchor=(0.36, 1.0))
    ax = axs[1]
    for ua in ["80", "100", "120", "150"]:
        u, i = xy(DATA["ia_ug"]["curves"][ua])
        ax.plot(u, i, color=BLUE, lw=2)
        x, y = mg[int(ua)]; m = y <= 12
        ax.plot(x[m], y[m], color=ORANGE, lw=2, ls=(0, (5, 3)))
        ax.text(u[-1] + 0.05, i[-1], f"{ua} V", fontsize=8, va="center")
    ax.set_xlim(-8, 0.6); ax.set_ylim(0, 12.5); ax.set_xlabel("Ug, V"); ax.set_ylabel("Ia, mA")
    title(ax, "Ia = f(Ug), Ua = 80 … 150 V")
    fig.suptitle("Reference sheet (solid) vs SPICE model (dashed), per triode", x=0.01, ha="left", fontsize=11)
    fig.savefig(os.path.join(out, "6n16b_model.png"), dpi=110); plt.close(fig)
    # numeric comparison at a few points for the page
    rows = []
    for ug, ua in ((0, 40), (0, 60), (-2, 100), (-2, 115), (-4, 140), (-4, 160), (-6, 180), (-6, 200)):
        u, i = xy(DATA["ia_ua"]["curves"][str(ug) if ug else "0"])
        ds = float(np.interp(ua, u, i)) if u[0] <= ua <= u[-1] else float("nan")
        x, y = mu[ug]; md = float(np.interp(ua, x, y))
        rows.append((ug, ua, ds, md))
    return rows


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "doc", "img"))
    os.makedirs(out, exist_ok=True)
    ia_ua(out); ia_ug(out); s_mu_ri(out); pulse(out)
    for ug, ua, ds, md in model(out):
        print(f"Ug {ug:3d} V, Ua {ua:3d} V: sheet {ds:5.2f} mA, model {md:5.2f} mA ({(md - ds) / ds * 100:+.0f} %)")
    print("figures in", out)
