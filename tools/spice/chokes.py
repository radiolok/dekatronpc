"""Plate chokes of the cell library: the only place for their values (owner, 2026-11-08, TRS v0.58,
doc/dinv_trigger_board.md §4). A choke sits in series with the plate resistor Ra, with its damping resistor across
it; SPICE builders and the KiCad sheet generators (tools/kicad) both take the values from here.

  TRIODE : Ra 10k gates on 6N16B triodes (NOR2/3/4_N16, NOT_N16), the 6N16B drivers of the benches and the D / C
           inverters inside the trigger cells: 0.68 mH || 10k (NOR2_N16 page, "Peaking inductor").
  PENTODE: Ra 15k gates with a 6Zh2B on the plate (NAND2_J2, A1OOI_N16J2, AOI211_J2N16, A2OOI_J2): La ~ Ra^2,
           0.68 mH x (15/10)^2 = 1.5 mH || 15k.
  CORE   : the RS core of every trigger (RSLATCH_J2N16 and its users, DFFP_J2N16): 1 mH, no damping resistor,
           with the screens at CORE_RG2 (RSLATCH_J2N16 page, "Speed-up options"; the DFFP_J2N16 values).
"""
TRIODE = ("680u", "10k")
PENTODE = ("1.5m", "15k")
CORE = ("1m", None)
CORE_RG2 = "12k"


def plate(name, node, ra, choke, vcc="vcc"):
    """SPICE lines of a plate load: Ra from vcc, then the choke (|| its damping resistor) to node.
    choke = (L, Rd) or None (plain Ra)."""
    if not choke or not choke[0]:
        return f"{name} {vcc} {node} {ra}\n"
    mid = f"lk_{name}"
    s = f"{name} {vcc} {mid} {ra}\nL{name} {mid} {node} {choke[0]}\n"
    if choke[1]: s += f"RL{name} {mid} {node} {choke[1]}\n"
    return s
