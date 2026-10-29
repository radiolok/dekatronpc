#!/usr/bin/env python3
"""Testbench definitions shared by the KiCad testbenches (tools/kicad/gen_aoi.py) and the plain-SPICE reference
runs, for A1OOI_N16J2 and A2OOI_J2 (sch/logic/A1OOI_N16J2/README.md, sch/logic/A2OOI_J2/README.md).

As latch_tb.py: ideal HV sources (PWL) -> divider -> driver (6N16B triode, Ra 10k; second triode cut off) ->
divider (C1 of the grid type) -> DUT input; the output -> one divider -> load tubes (6N16B, both grids on the net).
The input sequences, the .meas lines and the cell values are those of aoi_sweep.py, at fanout 6.
A1OOI_N16J2: the sheet holds two cells on one 6N16B. The bench drives cell 1; cell 2 has A2, B2, C2 on LV0
(-20 V, an LV "0") and Y2 open, so its triode only couples through the tube.
Node names are the KiCad ones (/A1, /Y1, /Y1_LV ...).

usage: aoi_tb.py [a1|a22 ...]     runs the plain-SPICE reference and prints the .meas values
"""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aoi_sweep as A   # noqa: E402
import latch_sweep as L  # noqa: E402
from latch_tb import pwl_pts, slots  # noqa: E402

P = dict(A.DEFAULT)
FANOUT = 6


def tb_of(key):
    c = A.CELLS[key]
    one = key == "a1"
    pin = {p: (p + "1" if one else p) for p in c['pins']}           # cell pin -> sheet pin
    src = {pin[p]: slots([s[i] for s in c['seq']], A.T) for i, p in enumerate(c['pins'])}
    y = "Y1" if one else "Y"
    meas = A.meas_lines(c, {p: "/" + pin[p] for p in c['pins']}, "/" + y, f"/{y}_LV")
    inputs = {pin[p]: A.c1_of(P, c['grid'][p]) for p in c['pins']}
    fixed = {"A2": "LV0", "B2": "LV0", "C2": "LV0", "Y2": "NC"} if one else {}
    states = " ".join("".join(map(str, s)) for s in c['seq'])
    return dict(key=key, name=c['name'], src=src, inputs=inputs, outputs={y: FANOUT}, fixed=fixed,
                stop=A.T * len(c['seq']), meas=meas, cell=c,
                note=f"States ({''.join(c['pins'])}) 2 us each: {states} (aoi_sweep.CELLS['{key}']).")


TBS = {"a1": lambda: tb_of("a1"), "a22": lambda: tb_of("a22")}


def cell_net(tb, p):
    """the drawn sheet, in plain SPICE (pentodes as aoi_sweep / latch_sweep, Cb to -50 V)"""
    s = ""
    if tb['key'] == "a1":
        for i in ("1", "2"):
            s += f"RA{i} vcc /Y{i} {p['Ra']}\n" + L.penta(i, f"/Y{i}", f"/A{i}", f"/B{i}", p)
        s += f"XT pt1 /C1 0 pt2 /C2 0 6N16B\nVT1 /Y1 pt1 0\nVT2 /Y2 pt2 0\n"
    else:
        s += f"RA vcc /Y {p['Ra']}\n" + L.penta("1", "/Y", "/A", "/B", p) + L.penta("2", "/Y", "/C", "/D", p)
    return s


def deck(tb):
    p = P
    s = f"* {tb['name']} testbench, plain SPICE\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\n"
    s += "VCC vcc 0 150\nVNB nb 0 -50\nVLV0 /LV0 0 -20\n"
    for k, (times, bits) in tb['src'].items():
        pts = " ".join(f"{t:.4f}u {v}" for t, v in pwl_pts(times, bits))
        s += f"VS{k} hs{k} 0 PWL({pts})\n" + L.div(f"s{k}", f"hs{k}", f"is{k}", p, p['C1g'])
        s += f"XD{k} pd{k} is{k} 0 pdx{k} nb 0 6N16B\nRD{k} vcc pd{k} 10k\nRDX{k} vcc pdx{k} 10k\n"
        s += L.div(f"d{k}", f"pd{k}", f"/{k}", p, tb['inputs'][k])
    for k, net in tb['fixed'].items():
        if net == "LV0": s += f"R0{k} /{k} /LV0 0.001\n"
    s += cell_net(tb, p)
    for o, ng in tb['outputs'].items():
        s += L.div(f"y{o}", f"/{o}", f"/{o}_LV", p, p['C1g'] * ng) + L.loads(f"/{o}_LV", p, ng, o)
    s += f".tran 5n {tb['stop']:.3f}u\n.control\nrun\n" + "\n".join(tb['meas']) + "\n.endc\n.end\n"
    return s


def run(tb):
    fn = os.path.join(tempfile.gettempdir(), f"aoi_tb_{tb['name']}.cir")
    open(fn, "w").write(deck(tb))
    o = subprocess.run([sys.executable, L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


if __name__ == "__main__":
    for k in sys.argv[1:] or list(TBS):
        tb = TBS[k](); m = run(tb)
        print(f"== {tb['name']}: {len(m)} values")
        print(A.fmt(k, "plain tb", FANOUT, m))
