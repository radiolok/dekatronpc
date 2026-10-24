#!/usr/bin/env python3
"""Digitize curves from scanned tube reference sheets (doc/digitizing_reference_sheets.md).

Commands (run with -h for options):
  render   PDF page -> PNG (300 dpi)                     needs pymupdf
  crop     cut one plot out of a page PNG
  grid     find grid line positions in a plot PNG
  scan     list curve crossings along rows or columns, in data units
  band     collect curve points inside a band around a rough guide, per curve
  order    assign row crossings to curves by left-to-right order
  fit      smooth a curve and resample it on a regular grid
  overlay  draw points over the plot PNG for checking
  plot     draw a digitized plot from the final JSON

Calibration file (cal.json), written by hand after `grid`:
  {"x": {"px": [x0, x1], "val": [v0, v1]},   two vertical grid lines and their axis values; add "log": true
                                             inside "x" or "y" for a logarithmic axis
   "y": {"px": [y0, y1], "val": [v0, v1]},   two horizontal grid lines and their axis values
   "grid_x_px": [...], "grid_y_px": [...]}   all grid lines (from `grid`), used to skip them
Points files are JSON: {"curve name": [[x, y], ...], ...} in data units.
"""
import argparse, json, sys
import numpy as np
from PIL import Image, ImageDraw


# ---------------------------------------------------------------- helpers
def load_bw(path, thr=128):
    return np.asarray(Image.open(path).convert("L")) < thr


def lin(cal, axis):
    """px <-> value converters for one axis; "log": true for a logarithmic axis"""
    c = cal[axis]
    (p0, p1), (v0, v1) = c["px"], c["val"]
    if c.get("log"):
        l0, l1 = np.log10(v0), np.log10(v1); k = (l1 - l0) / (p1 - p0)
        return (lambda p: 10 ** (l0 + (p - p0) * k)), (lambda v: p0 + (np.log10(v) - l0) / k)
    k = (v1 - v0) / (p1 - p0)
    return (lambda p: v0 + (p - p0) * k), (lambda v: p0 + (v - v0) / k)


def runs(line, minlen, maxlen):
    """centres and lengths of dark runs in a 1-D boolean array"""
    out = []
    i, n = 0, len(line)
    while i < n:
        if line[i]:
            j = i
            while j < n and line[j]:
                j += 1
            if minlen <= j - i <= maxlen:
                out.append(((i + j - 1) / 2, j - i))
            i = j
        else:
            i += 1
    return out


def near(v, arr, tol):
    return len(arr) > 0 and np.min(np.abs(np.asarray(arr) - v)) <= tol


def crossings(a, cal, mode, minlen, maxlen, skip):
    """all curve crossings: list of (x_val, y_val, run_len). mode rows: scan each row; cols: each column"""
    px2x, _ = lin(cal, "x"); px2y, _ = lin(cal, "y")
    gx, gy = cal.get("grid_x_px", []), cal.get("grid_y_px", [])
    H, W = a.shape
    res = []
    if mode == "rows":
        for y in range(H):
            if near(y, gy, skip):
                continue
            for c, L in runs(a[y], minlen, maxlen):
                if not near(c, gx, skip):
                    res.append((px2x(c), px2y(y), L))
    else:
        for x in range(W):
            if near(x, gx, skip):
                continue
            for c, L in runs(a[:, x], minlen, maxlen):
                if not near(c, gy, skip):
                    res.append((px2x(x), px2y(c), L))
    return res


def save(obj, path):
    json.dump(obj, open(path, "w"), indent=1)
    print("wrote", path)


# ---------------------------------------------------------------- commands
def cmd_render(a):
    import pymupdf
    doc = pymupdf.open(a.pdf)
    pages = range(len(doc)) if a.page is None else [a.page - 1]
    for i in pages:
        out = a.out.replace("{n}", str(i + 1)) if "{n}" in a.out else a.out
        doc[i].get_pixmap(dpi=a.dpi).save(out)
        print("wrote", out)


def cmd_crop(a):
    im = Image.open(a.png)
    W, H = im.size
    x0, y0, x1, y1 = a.box
    if max(a.box) <= 1.0:  # fractions of the page
        x0, x1, y0, y1 = x0 * W, x1 * W, y0 * H, y1 * H
    im.crop((int(x0), int(y0), int(x1), int(y1))).save(a.out)
    print("wrote", a.out, "size", int(x1 - x0), "x", int(y1 - y0))


def cmd_grid(a):
    b = load_bw(a.png)
    H, W = b.shape

    def lines(v, thr):
        idx = np.nonzero(v > thr)[0]; g = []
        for i in idx:
            if g and i - g[-1][-1] <= 2: g[-1].append(i)
            else: g.append([i])
        return [round(float(x[0] + x[-1]) / 2, 1) for x in g]
    vx = lines(b.sum(0) / H, a.thr); hy = lines(b.sum(1) / W, a.thr)
    for name, v in (("vertical x px", vx), ("horizontal y px", hy)):
        d = np.diff(v) if len(v) > 1 else []
        print(f"{name} ({len(v)}): {v}")
        if len(d):
            m = float(np.median(d))
            filled = [v[0]]
            for z in v[1:]:
                gap = z - filled[-1]
                if gap < 0.5 * m:                      # double detection of one line
                    filled[-1] = round((filled[-1] + z) / 2, 1); continue
                k = int(round(gap / m))
                for j in range(1, k):                 # missed lines inside a gap
                    filled.append(round(filled[-1] + gap / k, 1) if j == 1 else round(filled[-1] + gap / k, 1))
                filled.append(z)
            print(f"  spacing median {m:.2f} px; detected lines with gaps filled ({len(filled)}), use for grid_*_px:")
            print("  " + json.dumps(filled))
    print("image size", W, "x", H)
    # horizontal dark-run lengths over every 5th row: grid lines give the short peak, curves the longer tail
    from collections import Counter
    cnt = Counter(L for y in range(0, H, 5) for _, L in runs(b[y], 1, 60))
    print("run length px: count  ->  " + "  ".join(f"{L}:{cnt[L]}" for L in range(1, 21)))
    print("  pick --minlen just above the grid-line peak (grid lines are usually 2-3 px at 300 dpi)")


def cmd_scan(a):
    b = load_bw(a.png); cal = json.load(open(a.cal))
    px2x, x2px = lin(cal, "x"); px2y, y2px = lin(cal, "y")
    if a.mode == "rows":
        vals = np.arange(a.start, a.stop + 1e-9, a.step)
        gy = cal.get("grid_y_px", [])
        for v in vals:
            y = int(round(y2px(v)))
            if near(y, gy, a.skip) or not 0 <= y < b.shape[0]:
                continue
            cs = [px2x(c) for c, L in runs(b[y], a.minlen, a.maxlen) if not near(c, cal.get("grid_x_px", []), a.skip)]
            print(f"y={v:8.4g}: " + " ".join(f"{c:.4g}" for c in sorted(cs)))
    else:
        vals = np.arange(a.start, a.stop + 1e-9, a.step)
        gx = cal.get("grid_x_px", [])
        for v in vals:
            x = int(round(x2px(v)))
            if near(x, gx, a.skip) or not 0 <= x < b.shape[1]:
                continue
            cs = [px2y(c) for c, L in runs(b[:, x], a.minlen, a.maxlen) if not near(c, cal.get("grid_y_px", []), a.skip)]
            print(f"x={v:8.4g}: " + " ".join(f"{c:.4g}" for c in sorted(cs)))


def cmd_band(a):
    b = load_bw(a.png); cal = json.load(open(a.cal)); guides = json.load(open(a.guides))
    pts = np.array([(x, y) for x, y, L in crossings(b, cal, a.mode, a.minlen, a.maxlen, a.skip)])
    _, x2px = lin(cal, "x"); _, y2px = lin(cal, "y")
    out = {}
    for name, g in guides.items():
        g = np.array(sorted(g)); gpx = np.array([[x2px(x), y2px(y)] for x, y in g])
        P = np.array([[x2px(x), y2px(y)] for x, y in pts]) if len(pts) else np.zeros((0, 2))
        m = (P[:, 0] >= gpx[0, 0]) & (P[:, 0] <= gpx[-1, 0])
        yi = np.interp(P[:, 0], gpx[:, 0], gpx[:, 1])
        m &= np.abs(P[:, 1] - yi) <= a.width
        sel = pts[m]
        sel = sel[np.argsort(sel[:, 0])]
        out[name] = [[round(float(x), 5), round(float(y), 5)] for x, y in sel]
        print(f"{name}: {len(sel)} points")
    save(out, a.out)


def cmd_order(a):
    b = load_bw(a.png); cal = json.load(open(a.cal)); spec = json.load(open(a.curves))
    px2x, _ = lin(cal, "x"); _, y2px = lin(cal, "y")
    names = [c["name"] for c in spec]
    out = {n: [] for n in names}; used = skipped = 0
    for v in np.arange(a.start, a.stop + 1e-9, a.step):
        y = int(round(y2px(v)))
        if near(y, cal.get("grid_y_px", []), a.skip) or not 0 <= y < b.shape[0]:
            continue
        cs = sorted(px2x(c) for c, L in runs(b[y], a.minlen, a.maxlen) if not near(c, cal.get("grid_x_px", []), a.skip))
        exp = [c["name"] for c in spec if c.get("ymin", -1e99) <= v <= c.get("ymax", 1e99)]
        if len(cs) == len(exp):
            for n, x in zip(exp, cs): out[n].append([round(x, 5), round(float(v), 5)])
            used += 1
        else:
            skipped += 1
    print(f"rows used {used}, skipped {skipped} (crossing count did not match the curve count)")
    save(out, a.out)


def cmd_fit(a):
    pts = json.load(open(a.points)); out = {}
    for name, p in pts.items():
        p = np.array(p, dtype=float)
        if len(p) < a.deg + 2:
            print(f"{name}: too few points ({len(p)}), copied as is"); out[name] = p.tolist(); continue
        x, y = p[:, 0], p[:, 1]
        f = {"x": lambda t: t, "sqrt": lambda t: np.sqrt(np.clip(t - x.min(), 0, None)),
             "log": np.log, "inv": lambda t: 1 / t}[a.basis]
        keep = np.ones(len(x), bool)
        for _ in range(5):
            c = np.polyfit(f(x[keep]), y[keep], a.deg)
            r = np.abs(np.polyval(c, f(x)) - y)
            tol = max(a.tol, 2.5 * np.median(r[keep]))
            keep = r <= tol
        lo = a.lo if a.lo is not None else x[keep].min(); hi = a.hi if a.hi is not None else x[keep].max()
        xs = np.arange(lo, hi + 1e-9, a.step)
        out[name] = [[round(float(t), 5), round(float(np.polyval(c, f(t))), 5)] for t in xs]
        print(f"{name}: kept {keep.sum()}/{len(x)} points, max residual {r[keep].max():.4g}")
    save(out, a.out)


def cmd_overlay(a):
    cal = json.load(open(a.cal)); _, x2px = lin(cal, "x"); _, y2px = lin(cal, "y")
    im = Image.open(a.png).convert("RGB"); d = ImageDraw.Draw(im)
    cols = [(230, 60, 40), (40, 120, 220), (20, 160, 90), (220, 150, 0), (160, 60, 200)]
    for files in a.points:
        for i, (name, p) in enumerate(json.load(open(files)).items()):
            for x, y in p[::max(1, a.every)]:
                X, Y = x2px(x), y2px(y); r = a.r
                d.ellipse((X - r, Y - r, X + r, Y + r), fill=cols[i % len(cols)])
    im.save(a.out); print("wrote", a.out)


def cmd_plot(a):
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    pts = json.load(open(a.points))
    fig, ax = plt.subplots(figsize=(8, 5), constrained_layout=True)
    for name, p in pts.items():
        p = np.array(p, dtype=float)
        if len(p) == 0: continue
        ax.plot(p[:, 0], p[:, 1], color="#2a78d6", lw=2)
        ax.text(p[-1, 0], p[-1, 1], f" {name}", fontsize=8, va="center")
    ax.set_xlabel(a.xlabel); ax.set_ylabel(a.ylabel); ax.set_title(a.title, loc="left", fontsize=10)
    ax.grid(True, color="#e4e3dc"); fig.savefig(a.out, dpi=110); print("wrote", a.out)


# ---------------------------------------------------------------- CLI
def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="cmd", required=True)
    c = s.add_parser("render"); c.add_argument("pdf"); c.add_argument("--page", type=int); c.add_argument("--dpi", type=int, default=300)
    c.add_argument("--out", default="page{n}.png")
    c = s.add_parser("crop"); c.add_argument("png"); c.add_argument("--box", type=float, nargs=4, required=True,
                                                                     help="x0 y0 x1 y1 in px, or fractions of the page if all <= 1")
    c.add_argument("--out", required=True)
    c = s.add_parser("grid"); c.add_argument("png"); c.add_argument("--thr", type=float, default=0.45,
                                                                     help="share of dark pixels that makes a grid line")
    for name in ("scan", "band", "order"):
        c = s.add_parser(name); c.add_argument("png"); c.add_argument("--cal", required=True)
        c.add_argument("--minlen", type=int, default=5, help="shortest dark run that counts as a curve (px)")
        c.add_argument("--maxlen", type=int, default=30); c.add_argument("--skip", type=float, default=3,
                                                                        help="ignore runs this close to a grid line (px)")
        if name in ("scan", "order"):
            c.add_argument("--start", type=float, required=True); c.add_argument("--stop", type=float, required=True)
            c.add_argument("--step", type=float, required=True)
        if name == "scan": c.add_argument("--mode", choices=["rows", "cols"], default="rows")
        if name == "band":
            c.add_argument("--guides", required=True); c.add_argument("--width", type=float, default=15, help="band half-width (px)")
            c.add_argument("--mode", choices=["rows", "cols"], default="cols"); c.add_argument("--out", required=True)
        if name == "order": c.add_argument("--curves", required=True); c.add_argument("--out", required=True)
    c = s.add_parser("fit"); c.add_argument("points"); c.add_argument("--deg", type=int, default=3)
    c.add_argument("--basis", choices=["x", "sqrt", "log", "inv"], default="x"); c.add_argument("--step", type=float, required=True)
    c.add_argument("--lo", type=float); c.add_argument("--hi", type=float); c.add_argument("--tol", type=float, default=0.0)
    c.add_argument("--out", required=True)
    c = s.add_parser("overlay"); c.add_argument("png"); c.add_argument("--cal", required=True)
    c.add_argument("--points", nargs="+", required=True); c.add_argument("--every", type=int, default=1)
    c.add_argument("--r", type=float, default=3); c.add_argument("--out", required=True)
    c = s.add_parser("plot"); c.add_argument("points"); c.add_argument("--xlabel", default="x"); c.add_argument("--ylabel", default="y")
    c.add_argument("--title", default=""); c.add_argument("--out", required=True)
    a = p.parse_args()
    globals()["cmd_" + a.cmd](a)


if __name__ == "__main__":
    main()
