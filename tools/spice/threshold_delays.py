#!/usr/bin/env python3
"""Cell delays to the next stage's thresholds, for vtube_timing.json (owner, 2026-10-29).

A delay runs from the input crossing -5 V (LV) to the output crossing the level at which the next stage
has switched: 92 V for a falling output (the next stage sees a "0" below it) and 118 V for a rising one
(a "1" above it). The cell pages use 100 V for both; on AND-type arcs with a held g3 the plate reaches
100 V fast and then crawls, so 100 V under-states the delay (sch/logic/A1OOI_N16J2/README.md).
Each cell's own sweep deck is reused with only the target level changed.

usage: threshold_delays.py [--fanout 6] [--fall 92] [--rise 118] [cell ...]
prints, per cell, the iopath entries [Y rise, Y fall] in ns (the worst arc per input and direction).
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aoi_sweep as A, latch_sweep as L, dff_sweep as D, nand2_sweep as NA, nor2_sweep as NO, not_sweep as NT  # noqa: E402

FALL, RISE, FANOUT = 92, 118, 6


def retarget(deck):
    deck = re.sub(r"(targ v\([^)]*\) val=)100( fall)", rf"\g<1>{FALL}\2", deck)
    return re.sub(r"(targ v\([^)]*\) val=)100( rise)", rf"\g<1>{RISE}\2", deck)


def ngspice(deck):
    fn = os.path.join(tempfile.gettempdir(), f"thr_{os.getpid()}.cir")
    open(fn, "w").write(deck)
    o = subprocess.run([sys.executable, L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def gates(cell):
    """(deck, {meas: (pin, 'rise'|'fall' of Y)})"""
    if cell == "NAND2_J2":
        p = dict(R1="470k", R2="200k", C1g=3.9, C1g3=6.8, Cb=15, Ra="15k", Rg2="15k")
        return NA.deck(p, FANOUT), {"tphl_a": ("A", "fall"), "tplh_a": ("A", "rise"), "tphl_b": ("B", "fall"), "tplh_b": ("B", "rise")}
    if cell == "NOR2_N16":
        p = dict(R1="470k", R2="200k", C1g=3.9, Ra="10k")
        return NO.deck(p, FANOUT), {"tphl": ("A", "fall"), "tplh": ("A", "rise")}
    if cell == "NOT_N16":
        p = dict(R1="470k", R2="200k", C1g=3.9, Ra="10k")
        return NT.deck(p, FANOUT), {"tphl_a": ("A", "fall"), "tplh_a": ("A", "rise")}
    key = {"A1OOI_N16J2": "a1", "A2OOI_J2": "a22", "NOR4_N16": "n4"}[cell]
    c = A.CELLS[key]
    return A.deck(c, A.params(key), FANOUT), {k: (pin, do) for k, pin, di, do, t in A.arcs(c)}


# D latch (LATCH_J2N16): (D, E) per 2 us state; D toggles while E is high, E opens on both D levels
LSEQ = [(0, 1), (1, 1), (0, 1), (0, 0), (1, 0), (1, 1), (1, 0), (0, 0), (0, 1), (0, 0)]


def latch_deck():
    p = dict(L.BASE, **L.CHOSEN)
    s = f"* LATCH_J2N16 threshold delays\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    s += L.driver("d", [x[0] for x in LSEQ], "d", p, p['C1p'] + p['C1g'])
    s += L.driver("e", [x[1] for x in LSEQ], "e", p, 2 * p['C1g3'])
    s += D.dlatch("x", "d", "e", "q", "qn", p)[0]
    s += L.div("yq", "q", "yq", p, p['C1g'] * FANOUT) + L.loads("yq", p, FANOUT, "q")
    s += L.div("yn", "qn", "yn", p, p['C1g'] * FANOUT) + L.loads("yn", p, FANOUT, "n")
    arcs = {"d_r": ("d", "rise", 1, "rise"), "d_f": ("d", "fall", 2, "fall"),
            "e_r": ("e", "rise", 5, "rise"), "e_f": ("e", "rise", 8, "fall")}
    m = [f"meas tran {k} trig v({n}) val=-5 {di}=1 td={t*L.T-0.1:.2f}u targ v(q) val={RISE if do == 'rise' else FALL} {do}=1 td={t*L.T-0.1:.2f}u"
         for k, (n, di, t, do) in arcs.items()]
    s += f".tran 5n {L.T*len(LSEQ)}u\n.control\nrun\n" + "\n".join(m) + "\n.endc\n.end\n"
    return s, {"d_r": ("D", "rise"), "d_f": ("D", "fall"), "e_r": ("C", "rise"), "e_f": ("C", "fall")}


def dff_deck():
    """C falling -> Q, both directions: the output crossings and every C fall are found with WHEN, and the
    delay is taken from the last C fall before each crossing (dff_job)."""
    p = dict(L.BASE, **L.CHOSEN, edge="neg")
    s, _ = D.deck("dff", p, FANOUT, 1.0, 0.25)
    ct, cb, *_ = D.stimulus("dff", 1.0, 0.25, "neg")
    n = sum(1 for a, b in zip(cb, cb[1:]) if a and not b) + 1
    m = [f"meas tran cf{k} when v(c)=-5 fall={k}" for k in range(1, n + 1)]
    m += [f"meas tran qr{k} when v(q)={RISE} rise={k}" for k in range(1, 9)]
    m += [f"meas tran qf{k} when v(q)={FALL} fall={k}" for k in range(1, 9)]
    s = s.replace("\n.endc", "\n" + "\n".join(m) + "\n.endc")
    return s, None


def dff_job():
    deck, _ = dff_deck()
    m = ngspice(deck)
    cf = sorted(v for k, v in m.items() if k.startswith("cf"))
    out = {}
    for pre, d in (("qr", "rise"), ("qf", "fall")):
        ds = []
        for k, t in m.items():
            if k.startswith(pre) and t > 2.5e-6:
                prev = [c for c in cf if c < t]
                if prev: ds.append(t - prev[-1])
        out[d] = round(max(ds) * 1e9) if ds else None
    return "DFF_J2N16", {"C": [out["rise"], out["fall"]]}, out


CELLS = ["NOR2_N16", "NOR4_N16", "NOT_N16", "NAND2_J2", "A1OOI_N16J2", "A2OOI_J2", "LATCH_J2N16", "DFF_J2N16"]


def job(cell):
    if cell == "DFF_J2N16": return dff_job()
    if cell == "LATCH_J2N16": deck, mp = latch_deck()
    else:
        deck, mp = gates(cell); deck = retarget(deck)
    m = ngspice(deck)
    out = {}
    for k, (pin, d) in mp.items():
        if k not in m: continue
        r, f = out.get(pin, [0, 0])
        v = round(m[k] * 1e9)
        out[pin] = [max(r, v), f] if d == "rise" else [r, max(f, v)]
    if cell == "NOR2_N16": out["B"] = out["A"]
    return cell, out, {k: round(v * 1e9) for k, v in m.items() if k in mp}


if __name__ == "__main__":
    args = sys.argv[1:]
    for flag in ("--fanout", "--fall", "--rise"):
        if flag in args:
            i = args.index(flag); globals()[flag[2:].upper()] = int(args[i + 1]); del args[i:i + 2]
    cells = args or CELLS
    with Pool(7) as pool:
        for cell, out, raw in pool.map(job, cells):
            print(f"{cell:12s} fanout {FANOUT}, fall to {FALL} V, rise to {RISE} V: "
                  + ", ".join(f"{p}: [{r}, {f}]" for p, (r, f) in out.items()))
            print("   ", raw)
