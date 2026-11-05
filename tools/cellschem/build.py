#!/usr/bin/env python3
"""Draw the overview schematic of every tube logic cell.

    python3 tools/cellschem/build.py [CELL ...] [-o OUT_DIR]

Each figure is written to sch/logic/<CELL>/img/<cell>_schematic.svg (or into
OUT_DIR/<CELL>/ with -o, for previews). The figures redraw the netlist of the
KiCad sheet as one picture; edit the cell function, never the SVG.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cells_aoi  # noqa: E402
import cells_cf  # noqa: E402
import cells_latch  # noqa: E402
import cells_nor  # noqa: E402

LOGIC = os.path.normpath(os.path.join(HERE, "..", "..", "sch", "logic"))

# cell folder -> (file stem, drawing function)
CELLS = {
    "NOT_N16": ("not_n16_schematic", cells_nor.not_n16),
    "NOR2_N16": ("nor2_n16_schematic", cells_nor.nor2_n16),
    "NOR3_N16": ("nor3_schematic", cells_nor.nor3_n16),
    "NOR4_N16": ("nor4_schematic", cells_nor.nor4_n16),
    "NAND2_J2": ("nand2_j2_schematic", cells_aoi.nand2_j2),
    "A1OOI_N16J2": ("aoi21_schematic", cells_aoi.a1ooi_n16j2),
    "AOI211_J2N16": ("aoi211_schematic", cells_aoi.aoi211_j2n16),
    "A2OOI_J2": ("aoi22_schematic", cells_aoi.a2ooi_j2),
    "BUF_N16": ("buf_n16_schematic", cells_cf.buf_n16),
    "OR2_N16": ("or2_n16_schematic", cells_cf.or2_n16),
    "OR4_N16": ("or4_schematic", cells_cf.or4_n16),
    "RSLATCH_J2N16": ("latch_rs_schematic", cells_latch.rslatch),
    "DLATCH2_J2N16": ("latch_d2_schematic", cells_latch.dlatch2),
    "DFFP2_J2N16": ("dffp2_schematic", cells_latch.dffp2),
    "DFF_J2N16": ("latch_dff_schematic", lambda: cells_latch.dff("plain")),
    "DFFRN_J2N16X7": ("dffrn_schematic", lambda: cells_latch.dff("rn")),
    "DFFSN_J2N16X7": ("dffsn_schematic", lambda: cells_latch.dff("sn")),
}


# cells with a second figure: folder -> (file stem, drawing function)
EXTRA = {
    "DFFP2_J2N16": ("dffp_core_schematic", cells_latch.dffp_core),
}


def main(argv):
    out = None
    names = []
    it = iter(argv)
    for a in it:
        if a == "-o":
            out = next(it)
        else:
            names.append(a)
    for cell in names or CELLS:
        d = os.path.join(out or LOGIC, cell, "img") if not out else os.path.join(out, cell)
        os.makedirs(d, exist_ok=True)
        for stem, fn in [CELLS[cell]] + ([EXTRA[cell]] if cell in EXTRA else []):
            path = os.path.join(d, stem + ".svg")
            with open(path, "w", encoding="utf-8") as f:
                f.write(fn().render())
            print(path)


if __name__ == "__main__":
    main(sys.argv[1:])
