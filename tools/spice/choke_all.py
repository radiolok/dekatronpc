#!/usr/bin/env python3
"""Plate chokes in every cell (owner, 2026-11-08; doc/dinv_trigger_board.md §4): the decks of threshold_delays.py
with a choke La (|| Rd) in series with the plate resistors, delays to the next stage's thresholds (fall to 92 V,
rise to 118 V, input from -5 V), the lowest grid and the highest plate of the deck.

Which resistors get a choke (by the name in the deck):
  cell   : the plates of the cell (RA / RTX of the AOI and NOR3/4 sheets, RAx of NOT_N16, RAd of NAND2 / NOR2,
           the RS core RAx* and the in-cell inverters RIx* of the latches)
  driver : the 6N16B drivers of the inputs (RD*, RAda / RAdb), as a machine where every gate has its choke
  loads (RL*, RAl*) and screens (RS*) never.
Variants (CASES): "now" is the deck as the cell page has it (NOR2_N16 already carries 0.68 mH || 10k in every gate,
"no L" removes it); "cell" the cell's plates only; "all" the cell and its drivers.
  Lg  : choke of a gate plate, Lgd its damping resistor; Lc: the RS core plates (latches), Lcd its damping;
  Ld  : choke of the drivers (default Lg), Ldd its damping;
  Rg2 : screens of the 6Zh2B (latch core 15k -> 12k as DFFP_J2N16).

usage: choke_all.py [--fanout "2 6 10"] [cell ...]
"""
import os, re, sys
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import threshold_delays as T

GATE = {"Lg": "680u", "Lgd": "10k"}                      # NOR2_N16 since 2026-11-01
CORE = {"Lc": "1m", "Lcd": None}                          # DFFP_J2N16 / RSLATCH_J2N16 speed-up study
LATCH_INV = {"Lg": "680u", "Lgd": "10k"}                  # in-cell D / C inverter: a NOT_N16 half


def is_cell(cell, name):
    if cell in ("LATCH_J2N16", "DFF_J2N16"): return re.match(r"R[AI]x", name) is not None
    if cell == "NOT_N16": return name.startswith("RAx")
    if cell in ("NAND2_J2", "NOR2_N16"): return name == "RAd"
    return name == "RA" or name.startswith("RTX")


def is_driver(cell, name):
    return name.startswith("RD") or name in ("RAda", "RAdb")


def apply(deck, cell, v):
    """v: dict(where='now'|'nol'|'cell'|'all', Lg, Lgd, Lc, Lcd, Rg2)"""
    if v['where'] == 'nol':      # NOR2_N16 without its chokes
        deck = re.sub(r"^RA(\w+) vcc pl(\w+) (\S+)\nLA\w+ pl\w+ (\S+) \S+\n(RD\w+ pl\w+ \S+ \S+\n)?",
                      lambda m: f"RA{m.group(1)} vcc {m.group(4)} {m.group(3)}\n", deck, flags=re.M)
        return deck
    out = []
    for line in deck.split("\n"):
        m = re.match(r"^(R\w+) vcc (\S+) (\S+)$", line)
        if m and v['where'] != 'now':
            name, node, val = m.groups()
            if name.startswith("RS") and v.get('Rg2') and cell in ("LATCH_J2N16", "DFF_J2N16"):
                line = f"{name} vcc {node} {v['Rg2']}"
            elif is_cell(cell, name) or (v['where'] == 'all' and is_driver(cell, name)):
                core = cell in ("LATCH_J2N16", "DFF_J2N16") and name.startswith("RA")
                if core: L, Rd = v['Lc'], v['Lcd']
                elif is_cell(cell, name): L, Rd = v['Lg'], v['Lgd']
                else: L, Rd = v.get('Ld', v['Lg']), v.get('Ldd', v['Lgd'])     # drivers: 10k triodes
                if L:
                    line = f"{name} vcc lk{name} {val}\nLK{name} lk{name} {node} {L}"
                    if Rd: line += f"\nRK{name} lk{name} {node} {Rd}"
        out.append(line)
    deck = "\n".join(out)
    if v['where'] != 'now' and "method=gear" not in deck:
        deck = deck.replace(".tran", ".options method=gear\n.tran", 1)
    return deck


def extremes(deck):
    """meas lines: the lowest grid and the highest plate of every tube (6N16B: plates 1, 4, grids 2, 5;
    6Zh2B: plate 1, g3 2, g1 5) after 0.5 us; the ideal-source inputs is*/hs* are skipped"""
    grids, plates = set(), set()
    for m in re.finditer(r"^X\w+ (.+) (6N16B|6Zh2B)\b", deck, re.M):
        n = m.group(1).split()
        g = (n[1], n[4]) if m.group(2) == "6N16B" else (n[1], n[4])
        grids.update(x for x in g if x not in ("0", "nb", "nb20") and not x.startswith(("is", "hs")))
        plates.add(n[0])
        if m.group(2) == "6N16B": plates.add(n[3])
    stop = float(re.search(r"^\.tran \S+ ([\d.]+)u", deck, re.M).group(1))
    L = [f"meas tran gmin_{g} min v({g}) from=0.5u to={stop}u" for g in sorted(grids)]
    L += [f"meas tran pmax_{p} max v({p}) from=0.5u to={stop}u" for p in sorted(plates)]
    return deck.replace("\n.endc", "\n" + "\n".join(L) + "\n.endc", 1)


def job(arg):
    cell, vname, v, n = arg
    T.FANOUT = n
    if cell == "DFF_J2N16":
        deck, _ = T.dff_deck(); mp = None
    elif cell == "LATCH_J2N16":
        deck, mp = T.latch_deck()
    else:
        deck, mp = T.gates(cell); deck = T.retarget(deck)
    m = T.ngspice(extremes(apply(deck, cell, v)))
    out = {}
    if mp is None:   # DFF: delay from the last C fall before each output crossing (threshold_delays.dff_job)
        cf = sorted(x for k, x in m.items() if k.startswith("cf"))
        for pre, d in (("qr", 0), ("qf", 1)):
            ds = [t - [c for c in cf if c < t][-1] for k, t in m.items()
                  if k.startswith(pre) and t > 2.5e-6 and any(c < t for c in cf)]
            out.setdefault("C", [None, None])[d] = round(max(ds) * 1e9) if ds else None
    else:
        for k, (pin, d) in mp.items():
            if k not in m: continue
            r, f = out.get(pin, [0, 0])
            x = round(m[k] * 1e9)
            out[pin] = [max(r, x), f] if d == "rise" else [r, max(f, x)]
    gk = min((k for k in m if k.startswith("gmin_")), key=lambda k: m[k], default=None)
    pk = max((k for k in m if k.startswith("pmax_")), key=lambda k: m[k], default=None)
    return cell, vname, n, out, (gk[5:], m[gk]) if gk else None, (pk[5:], m[pk]) if pk else None


def cases(cell):
    if cell == "NOR2_N16":
        return [("no L", dict(where="nol")), ("now: 0.68m||10k all", dict(where="now"))]
    if cell in ("LATCH_J2N16", "DFF_J2N16"):
        return [("now", dict(where="now")),
                ("cell: core 1m, inv .68||10k", dict(where="cell", **CORE, **LATCH_INV)),
                ("all: core 1m, inv+drv .68||10k", dict(where="all", **CORE, **LATCH_INV)),
                ("all + Rg2 12k", dict(where="all", **CORE, **LATCH_INV, Rg2="12k"))]
    c = [("now", dict(where="now")), ("cell .68||10k", dict(where="cell", **GATE)),
         ("all .68||10k", dict(where="all", **GATE))]
    if cell in ("NAND2_J2", "A1OOI_N16J2", "AOI211_J2N16", "A2OOI_J2"):   # Ra 15k: La ~ Ra^2
        c += [("cell 1.5m||15k", dict(where="cell", Lg="1.5m", Lgd="15k")),
              ("all 1.5m||15k, drv .68||10k", dict(where="all", Lg="1.5m", Lgd="15k", Ld="680u", Ldd="10k"))]
    return c


if __name__ == "__main__":
    args = sys.argv[1:]
    fan = [2, 6, 10]
    if "--fanout" in args:
        i = args.index("--fanout"); fan = [int(x) for x in args[i + 1].split()]; del args[i:i + 2]
    cells = args or T.CELLS
    jobs = [(c, vn, v, n) for c in cells for vn, v in cases(c) for n in fan]
    with Pool(16) as pool:
        for cell, vn, n, out, g, p in pool.map(job, jobs):
            arcs = ", ".join(f"{k}: [{r}, {f}]" for k, (r, f) in out.items())
            print(f"{cell:12s} | {vn:32s} | N={n:2d} | {arcs} | grid min {g[1]:6.1f} ({g[0]}) | plate max {p[1]:5.1f} ({p[0]})")
