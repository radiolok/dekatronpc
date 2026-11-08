#!/usr/bin/env python3
"""KiCad testbench against its plain-SPICE reference, every .meas value (the cell pages quote the agreement).

usage: kicad_parity.py [CELL ...]      (default: every cell below)
Runs tools/spice/sim_kicad.sh on sch/logic/<CELL>/<CELL>_tb.kicad_sch and the matching reference
(latch_tb / aoi_tb / pff_tb; NOT_N16 and NAND2_J2: their sweep deck at the bench's fanout and sequence), and prints
the number of common values and the largest relative difference. Values below 1 (V or s near zero) are
compared absolutely (1 mV, 0.1 ns).
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
SCH = os.path.normpath(os.path.join(HERE, "..", "..", "sch", "logic"))


def kicad(cell):
    out = tempfile.mkdtemp(prefix=f"par_{cell}_")
    o = subprocess.run(["bash", os.path.join(HERE, "sim_kicad.sh"), os.path.join(SCH, cell, f"{cell}_tb.kicad_sch"), out],
                       capture_output=True, text=True, timeout=900).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def reference(cell):
    if cell in ("RSLATCH_J2N16", "DLATCH2_J2N16", "DFF_J2N16", "DFFRN_J2N16X7", "DFFSN_J2N16X7"):
        import latch_tb as T
        key = {"RSLATCH_J2N16": "rslatch", "DLATCH2_J2N16": "dlatch2", "DFF_J2N16": "dff",
               "DFFRN_J2N16X7": "dffrn", "DFFSN_J2N16X7": "dffsn"}[cell]
        return T.run(T.TBS[key]())
    if cell == "DFFP2_J2N16":
        import pff_tb as T
        return T.run(T.bench())
    if cell == "NOT_N16":
        import not_sweep as N
        return N.run(("NOT_N16", N.CELL, 10))[2]
    if cell == "NAND2_J2":
        import nand2_sweep as N
        N.SEQ_A, N.SEQ_B = N.KICAD_A, N.KICAD_B
        return N.run(("NAND2_J2", N.CELL, 10))[2]
    import aoi_tb as T
    key = {"A1OOI_N16J2": "a1", "AOI211_J2N16": "a211", "A2OOI_J2": "a22", "NOR3_N16": "n3", "NOR4_N16": "n4"}[cell]
    return T.run(T.TBS[key]())


def job(cell):
    a, b = kicad(cell), reference(cell)
    common = sorted(set(a) & set(b))
    worst = (0.0, None)
    for k in common:
        x, y = a[k], b[k]
        tol = 1e-3 if abs(y) > 1e-3 else 1e-10          # V or s
        d = abs(x - y) / abs(y) if abs(y) > 1 else abs(x - y) / (1 if abs(y) > 1e-3 else 1e-7)
        if abs(x - y) > tol and d > worst[0]: worst = (d, k)
    return cell, len(a), len(b), len(common), worst


CELLS = ["NOT_N16", "NAND2_J2", "NOR3_N16", "NOR4_N16", "A1OOI_N16J2", "AOI211_J2N16", "A2OOI_J2", "RSLATCH_J2N16",
         "DLATCH2_J2N16", "DFF_J2N16", "DFFRN_J2N16X7", "DFFSN_J2N16X7", "DFFP2_J2N16"]

if __name__ == "__main__":
    with Pool(13) as pool:
        for cell, na, nb, nc, (d, k) in pool.map(job, sys.argv[1:] or CELLS):
            print(f"{cell:14s} KiCad {na:3d}, reference {nb:3d}, common {nc:3d}: worst {d*100:.3f} % ({k})")
