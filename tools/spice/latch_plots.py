#!/usr/bin/env python3
"""Build every figure of the latch / flip-flop page (sch/logic/RSLATCH_J2N16/README.md) from the sources in the repo.

usage: tools/spice/latch_plots.py [OUT_DIR]          (default: each figure into sch/logic/<CELL>/img)

Writes
  latch_rs_cell.png, latch_d2_cell.png, latch_dff_cell.png   cell sheets exported from KiCad
  latch_dff_tb.png                                           the DFF testbench root sheet
  latch_rs_tran.png, latch_dff_tran.png                      KiCad testbench waveforms (ngspice)
  latch_fanout.png                                           delays and timing limits vs fanout
and prints the input thresholds (slow ramps), the timing limits and the register-to-register clock limit.
Needs kicad-cli, rsvg-convert, matplotlib, Pillow and KiCad's libngspice. Style as tools/spice/not_plots.py.
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
import latch_sweep as L    # noqa: E402
import latch_timing as LT  # noqa: E402
import dff_sweep as D      # noqa: E402

SCH = os.path.join(REPO, "sch", "logic")
P = dict(L.BASE, **L.CHOSEN, edge="neg")
GRIDS = (2, 4, 6, 8, 10)
IMG_CELL = {"latch_rs_cell.png": "RSLATCH_J2N16", "latch_rs_tran.png": "RSLATCH_J2N16", "latch_fanout.png": "RSLATCH_J2N16",
            "latch_d2_cell.png": "DLATCH2_J2N16",
            "latch_dff_cell.png": "DFF_J2N16", "latch_dff_tb.png": "DFF_J2N16", "latch_dff_tran.png": "DFF_J2N16",
            "dffrn_cell.png": "DFFRN_J2N16X7", "dffrn_tb.png": "DFFRN_J2N16X7", "dffrn_tran.png": "DFFRN_J2N16X7",
            "dffsn_cell.png": "DFFSN_J2N16X7", "dffsn_tb.png": "DFFSN_J2N16X7", "dffsn_tran.png": "DFFSN_J2N16X7"}

def dest(out, png):
    """Where a figure goes: OUT_DIR if given, else the img/ folder of the cell page that shows it."""
    d = out or os.path.join(REPO, "sch", "logic", IMG_CELL[png], "img")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, png)


BLUE, ORANGE, GREEN = "#2a78d6", "#eb6834", "#2e9e6a"
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


def crop_png(svg, png, width=3000, m=30):
    subprocess.run(["rsvg-convert", "-w", str(width), "-b", "white", svg, "-o", png + ".full.png"], check=True)
    im = Image.open(png + ".full.png").convert("RGB")
    a = np.asarray(im).astype(int)
    ys, xs = np.nonzero(a.max(axis=2) - a.min(axis=2) > 60)
    # drop the page frame and title block: keep the bounding box of the colour inside 4..92 % of the page
    h, w = a.shape[:2]
    keep = (xs > 0.03 * w) & (xs < 0.97 * w) & (ys > 0.04 * h) & (ys < 0.80 * h)
    xs, ys = xs[keep], ys[keep]
    im.crop((xs.min() - m, ys.min() - m, xs.max() + m, ys.max() + m)).save(png)
    os.remove(png + ".full.png")


def schematics(out, tmp):
    for tb, pages in (("RSLATCH_J2N16_tb", {"RSLATCH_J2N16_tb-DUT.svg": "latch_rs_cell.png"}),
                      ("DLATCH2_J2N16_tb", {"DLATCH2_J2N16_tb-DUT.svg": "latch_d2_cell.png"}),
                      ("DFF_J2N16_tb", {"DFF_J2N16_tb-DUT.svg": "latch_dff_cell.png", "DFF_J2N16_tb.svg": "latch_dff_tb.png"}),
                      ("DFFRN_J2N16X7_tb", {"DFFRN_J2N16X7_tb-DUT.svg": "dffrn_cell.png", "DFFRN_J2N16X7_tb.svg": "dffrn_tb.png"}),
                      ("DFFSN_J2N16X7_tb", {"DFFSN_J2N16X7_tb-DUT.svg": "dffsn_cell.png", "DFFSN_J2N16X7_tb.svg": "dffsn_tb.png"})):
        svg = os.path.join(tmp, tb)
        os.makedirs(svg, exist_ok=True)
        subprocess.run(["kicad-cli", "sch", "export", "svg", "-e", "-o", svg, os.path.join(SCH, tb[:-len("_tb")], tb + ".kicad_sch")],
                       check=True, capture_output=True)
        for s, png in pages.items():
            crop_png(os.path.join(svg, s), dest(out, png), width=2600 if "tb.svg" in s else 3000)


def kicad_waves(tb, vecs, tmp):
    sch = os.path.join(SCH, tb[:-len("_tb")], tb + ".kicad_sch")
    cir = os.path.join(tmp, tb + ".cir")
    subprocess.run(["kicad-cli", "sch", "export", "netlist", "--format", "spice", "-o", cir, sch], check=True, capture_output=True)
    txt = open(cir).read().replace('.include "/../', '.include "%s/../' % os.path.dirname(sch))
    wave = os.path.join(tmp, tb + ".txt")
    txt = re.sub(r"^\.end\s*$", ".control\nrun\nwrdata %s %s\n.endc\n.end\n" % (wave, " ".join("v(%s)" % v for v in vecs)),
                 txt, flags=re.M)
    open(cir, "w").write(txt)
    res = meas(ngspice(cir))
    d = np.loadtxt(wave)
    return res, d[:, 0] * 1e6, [d[:, 1 + 2 * i] for i in range(len(vecs))]


def wave_fig(path, title, t, rows, labels=None, period=None):
    fig, axs = plt.subplots(len(rows), 1, sharex=True, figsize=(10, 1.75 * len(rows)), constrained_layout=True)
    tend = t[-1]
    for ax, (name, y, fam) in zip(axs, rows):
        ax.plot(t, y, color=BLUE if fam == "hv" else GREEN, lw=1.8)
        ax.set_title(name, loc="left", fontsize=10); ax.set_ylabel("V")
        if fam == "hv":
            refline(ax, 150, "+150", tend * 1.005); refline(ax, 50, "+50", tend * 1.005); ax.set_ylim(20, 165)
        else:
            refline(ax, 10, "+10", tend * 1.005); refline(ax, -20, "−20", tend * 1.005)
            refline(ax, -50, "Ug limit", tend * 1.005); ax.set_ylim(-55, 15)
    if labels:
        for k, s in enumerate(labels):
            axs[0].text(L.T * k + L.T / 2, -46, s, ha="center", va="center", fontsize=8, color=MUTED)
    axs[-1].set_xlabel("t, µs"); axs[-1].set_xlim(0, tend)
    fig.suptitle(title, x=0.01, ha="left", fontsize=12)
    fig.savefig(path, dpi=105)
    plt.close(fig)


def waveforms(out, tmp):
    rs, t, v = kicad_waves("RSLATCH_J2N16_tb", ["/S", "/R", "/E", "/Q", "/QN", "/DUT/FQ"], tmp)
    rows = [("S (LV)", v[0], "lv"), ("R (LV)", v[1], "lv"), ("E (LV, two g3)", v[2], "lv"),
            ("Q (HV)", v[3], "hv"), ("QN (HV)", v[4], "hv"), ("FQ (LV, cross-coupled grid of triode A)", v[5], "lv")]
    wave_fig(dest(out, "latch_rs_tran.png"), "RSLATCH_J2N16: KiCad testbench in ngspice, fanout 6 on Q and QN",
             t, rows, labels=["SRE\n011", "000", "100", "101", "100", "010", "011", "001", "101", "001", "011", "000"])
    df, t, v = kicad_waves("DFF_J2N16_tb", ["/C", "/D", "/DUT/QM", "/DUT/ES", "/Q", "/QN"], tmp)
    rows = [("C (LV, clock 1 MHz)", v[0], "lv"), ("D (LV)", v[1], "lv"), ("QM (HV, master Q)", v[2], "hv"),
            ("ES (LV, slave enable = ~C)", v[3], "lv"), ("Q (HV)", v[4], "hv"), ("QN (HV)", v[5], "hv")]
    wave_fig(dest(out, "latch_dff_tran.png"), "DFF_J2N16: KiCad testbench in ngspice, 1 MHz, fanout 6",
             t, rows)
    reset_waveforms(out, tmp)
    return rs, df


def reset_waveforms(out, tmp):
    for cell, pin, node, png in (("DFFRN_J2N16X7", "RN", "FQNM", "dffrn_tran.png"), ("DFFSN_J2N16X7", "SN", "FQM", "dffsn_tran.png")):
        _, t, v = kicad_waves(cell + "_tb", ["/C", "/D", f"/{pin}", f"/DUT/{node}", "/Q", "/QN"], tmp)
        rows = [("C (LV, clock 1 MHz)", v[0], "lv"), ("D (LV)", v[1], "lv"),
                (f"{pin} (the reset line: idle -20 V, GND = asserted)", v[2], "lv"),
                (f"{node} (LV, master feedback grid, the diode's cathode)", v[3], "lv"),
                ("Q (HV)", v[4], "hv"), ("QN (HV)", v[5], "hv")]
        wave_fig(dest(out, png), f"{cell}: KiCad testbench in ngspice, 1 MHz, fanout 6, {pin} asserted 8.2 to 11.7 us", t, rows)


THRESH_DECK = """* input thresholds by a slow ramp: LV inputs as Thevenin sources of the divider (V, 140k)
.include {libs}/6Zh2B.sub
.include {libs}/6N16B.sub
VCC vcc 0 150
VNB nb 0 -50
VS vs 0 {vs}
VR vr 0 {vr}
VE ve 0 {ve}
RS vs s 140k
RR vr r 140k
RE ve e 140k
{cell}
.tran 50n 400u
.control
run
meas tran th find v({node}) when v(qn)=100 fall=1 td=16u
.endc
.end
"""


def thresholds(tmp):
    """the latch starts reset (Q = 0); ramp one input from -20 V to +10 V in 400 us with the other held"""
    cell = L.rslatch("x", "s", "r", "e", "q", "qn", P)[0]
    cell += L.div("yq", "q", "yq", P, P['C1g'] * 6) + L.div("yn", "qn", "yn", P, P['C1g'] * 6)
    cell += L.loads("yq", P, 6, "q") + L.loads("yn", P, 6, "n")
    ramp = "PWL(0 -20 20u -20 420u 10)"
    reset = "PWL(0 10 10u 10 12u -20)"            # R pulse resets the latch first
    out = {}
    for nm, vs, ve, node in (("S, E high", ramp, "10", "s"),
                             ("E, S high", "PWL(0 -20 14u -20 15u 10)", "PWL(0 10 10u 10 12u -20 20u -20 420u 10)", "e")):
        deck = os.path.join(tmp, "th.cir")
        open(deck, "w").write(THRESH_DECK.format(libs=L.LIBS, vs=vs, vr=reset, ve=ve, cell=cell, node=node))
        out[nm] = meas(ngspice(deck)).get("th", float("nan"))
    return out


def fmax_job(arg):
    edge, n = arg
    ok = lambda per: "ERR" not in D.fmt(*D.run(("shift", edge, dict(P, edge=edge), n, per, 0.25)))
    lo, hi = 0.4, 3.0
    if not ok(hi): return edge, n, float("nan")
    while hi - lo > 0.02:
        mid = (lo + hi) / 2
        if ok(mid): hi = mid
        else: lo = mid
    return edge, n, hi


def fanout(out):
    with Pool(min(8, os.cpu_count() or 1)) as pool:
        rows = pool.map(L.run, [("rs", P, n) for n in GRIDS])
        tim = pool.map(LT.bisect, [(k, P, n) for k in ("wmin", "setup", "hold") for n in GRIDS])
        dffr = pool.map(D.run, [("dff", "neg", P, n, 4.0, 0.25) for n in GRIDS])
        fm = pool.map(fmax_job, [(e, n) for e in ("neg", "pos") for n in GRIDS])
    g = lambda m, k: m.get(k, float("nan")) * 1e9
    er = [max(g(m, "er_qr"), g(m, "er_qrn")) for _, _, m in rows]
    sr = [max(g(m, "sr_qr"), g(m, "sr_qrn")) for _, _, m in rows]
    wmin = [dt for k, n, x, dt in tim if k == "wmin"]
    setup = [dt for k, n, x, dt in tim if k == "setup"]
    tcq = [m.get("tcq_r", float("nan")) * 1e9 for *_, m, _ in dffr]
    fneg = [1 / per for e, n, per in fm if e == "neg"]
    fpos = [1 / per for e, n, per in fm if e == "pos"]
    fig, axs = plt.subplots(1, 2, figsize=(11, 4), constrained_layout=True)
    ax = axs[0]
    for y, c, lab in ((tcq, ORANGE, "DFF: C↓ → Q"), (wmin, MUTED, "RS: shortest E pulse"), (setup, GREEN, "RS: setup S before E↓"),
                      (er, BLUE, "RS: E↑ → Q/QN (later output)"), (sr, "#8a5cc2", "RS: S↑ → Q/QN")):
        ax.plot(GRIDS, y, color=c, lw=2, marker="o", ms=7, mec=SURF, mew=2, label=lab)
        ax.text(GRIDS[-1] + 0.2, y[-1], "%.0f" % y[-1], va="center", fontsize=8)
    ax.set_xlim(1, GRIDS[-1] + 1.5); ax.set_ylim(0, None); ax.set_xticks(GRIDS)
    ax.set_xlabel("grids on each output net (fanout)"); ax.set_ylabel("ns")
    ax.set_title("Delays and timing limits (LV −5 V → HV 100 V)", loc="left", fontsize=10)
    ax.legend(frameon=False, loc="upper left", fontsize=8)
    ax = axs[1]
    ax.plot(GRIDS, fneg, color=BLUE, lw=2, marker="o", ms=7, mec=SURF, mew=2, label="falling edge (chosen)")
    ax.plot(GRIDS, fpos, color=ORANGE, lw=2, marker="o", ms=7, mec=SURF, mew=2, label="rising edge (master on ~C)")
    ax.axhline(1.0, color=MUTED, ls=(0, (4, 3)), lw=1); ax.text(GRIDS[-1] + 0.2, 1.0, "1 MHz", va="center", fontsize=8, color=MUTED)
    ax.set_xlim(1, GRIDS[-1] + 1.5); ax.set_ylim(0, None); ax.set_xticks(GRIDS)
    ax.set_xlabel("grids on Q (fanout)"); ax.set_ylabel("MHz")
    ax.set_title("Register → register clock limit (two DFF in a row)", loc="left", fontsize=10)
    ax.legend(frameon=False, loc="lower left", fontsize=8)
    fig.savefig(dest(out, "latch_fanout.png"), dpi=105)
    plt.close(fig)
    return rows, tim, dffr, fm


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
    with tempfile.TemporaryDirectory() as tmp:
        schematics(out, tmp)
        rs, df = waveforms(out, tmp)
        th = thresholds(tmp)
        rows, tim, dffr, fm = fanout(out)
    print("RSLATCH tb .meas:", ", ".join("%s=%.4g" % kv for kv in sorted(rs.items())))
    print("DFF tb .meas:", ", ".join("%s=%.4g" % kv for kv in sorted(df.items())))
    print("input thresholds (LV, latch flips):", th)
    for r in rows: print(L.fmt(*r))
    for k, n, x, dt in tim: print(f"{k:6s} N={n:2d}: {dt:5.0f} ns on the LV grids")
    for r in dffr: print(D.fmt(*r))
    for e, n, per in fm: print(f"shift {e} N={n:2d}: shortest period {per*1e3:4.0f} ns ({1/per:.2f} MHz)")
    print("figures in", out or "sch/logic/<CELL>/img")
