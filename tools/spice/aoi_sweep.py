#!/usr/bin/env python3
"""AND-OR-INVERT cells A1OOI_N16J2 and A2OOI_J2 (AOI22), and NOR4_N16: transient sweep over fanout.

A1OOI_N16J2  Y = ~((A & B) | C)   6Zh2B: A on g1, B on g3; one 6N16B triode: C on the grid; one plate Y.
                                   This is one half of RSLATCH_J2N16 without the feedback.
A2OOI_J2     Y = ~((A & B) | (C & D))   two 6Zh2B on one plate: A, C on g1; B, D on g3.
Levels as REQ-MOD-012: LV inputs (1 = +10, 0 = -20 V), HV plate output (1 = +150, 0 = +50 V).
Plate through Ra to +150 V, screens through Rg2 from +150 V, Cb on every g3 (as NAND2_J2).
Chain per input: ideal HV pulse -> divider -> 6N16B triode driver (Ra 10k, the fastest driver of the
library, so the worst kick) -> divider with C1 for that grid type -> DUT input;
Y -> divider (C1 = C1g x grids) -> N triode grids (N/2 load 6N16B).
In A1OOI the second triode of the 6N16B is the other AOI of the sheet: here its grid sits at -20 V
and its plate on its own Ra (it only couples through CPP).
Delays: input crossing -5 V to Y crossing 100 V. States 2 us each, see SEQ.

NOR4_N16     Y = ~(A | B | C | D)  two 6N16B, all four triodes on one plate, Ra 10k (as NOR2_N16).

OR4_N16      Y = A | B | C | D     two 6N16B, cathode followers with the cathodes tied (OR2_N16 widened), LV output.

usage: aoi_sweep.py [a1|a22|n4|o4 ...] [--grids 2,6,10] [cases.py]
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import latch_sweep as L   # noqa: E402  (penta, div, driver, loads, pwl, T)
NGRUN = os.path.join(HERE, "ngrun.py")
LIBS = L.LIBS
T = L.T

DEFAULT = dict(R1="470k", R2="200k", Ra="15k", Rg2="15k", Cb=15, C1g=3.9, C1p=2.7, C1g3=6.8, C1fol=2.7)

CELLS = {
    "a1": dict(name="A1OOI_N16J2", pins="ABC", f=lambda a, b, c: 1 - ((a & b) | c),
               grid=dict(A="g1", B="g3", C="tri"),
               seq=[(0, 0, 0), (1, 0, 0), (1, 1, 0),   # B rises with A held high
                    (0, 1, 0), (1, 1, 0), (1, 0, 0),   # A falls / rises with B held high (g3 Miller)
                    (1, 0, 1), (1, 0, 0),              # C with A high, B low
                    (0, 0, 0), (0, 1, 0), (0, 1, 1),   # C with B held high (g3 sees the plate swing)
                    (0, 1, 0), (1, 1, 0),
                    (1, 0, 1),                         # hazard: B falls, C rises together (Y stays 0)
                    (1, 1, 1), (1, 1, 0), (0, 0, 0)]),
    "a22": dict(name="A2OOI_J2", pins="ABCD", f=lambda a, b, c, d: 1 - ((a & b) | (c & d)),
                grid=dict(A="g1", B="g3", C="g1", D="g3"),
                seq=[(0, 0, 0, 0), (1, 0, 0, 0), (1, 1, 0, 0), (0, 1, 0, 0), (1, 1, 0, 0), (1, 0, 0, 0),
                     (1, 0, 1, 0), (1, 0, 1, 1), (1, 0, 0, 1), (1, 0, 1, 1), (1, 0, 1, 0),
                     (0, 0, 1, 0), (0, 1, 1, 0),        # B held high on the idle pentode ...
                     (0, 1, 1, 1), (0, 1, 1, 0), (0, 1, 1, 1),   # ... while D swings the plate
                     (0, 1, 0, 1), (1, 1, 0, 1), (1, 1, 1, 1), (1, 1, 1, 0),
                     (1, 0, 1, 1),                      # hazard: B falls, D rises together (Y stays 0)
                     (1, 1, 1, 0), (0, 0, 0, 0)]),
    # NOR4_N16: two 6N16B, all four triodes on one plate, Ra as NOR2_N16
    "n4": dict(name="NOR4_N16", pins="ABCD", f=lambda a, b, c, d: 1 - (a | b | c | d),
               grid=dict(A="tri", B="tri", C="tri", D="tri"), p=dict(Ra="10k"),
               seq=[(0, 0, 0, 0), (1, 0, 0, 0), (0, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 0), (0, 0, 1, 0),
                    (0, 0, 0, 0), (0, 0, 0, 1), (0, 0, 0, 0), (1, 1, 1, 1), (0, 1, 1, 1),   # all high: lowest VOL
                    (0, 0, 0, 0), (1, 0, 0, 0),
                    (0, 1, 0, 0),                          # hazard: A falls, B rises together (Y stays 0)
                    (0, 0, 0, 0)]),
    # OR4_N16: two 6N16B as cathode followers, the four cathodes tied, one Rs || Cs and Rk (OR2_N16 widened).
    # LV output straight onto the load grids; each input on its own divider (follower grid, C1 2.7 pF).
    "o4": dict(name="OR4_N16", pins="ABCD", f=lambda a, b, c, d: a | b | c | d, out="LV",
               grid=dict(A="fol", B="fol", C="fol", D="fol"), p=dict(Rs="2.2k", Cs="100p", Rk="12k"),
               seq=[(0, 0, 0, 0), (1, 0, 0, 0), (0, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 0), (0, 0, 1, 0),
                    (0, 0, 0, 0), (0, 0, 0, 1), (0, 0, 0, 0), (1, 1, 1, 1), (0, 0, 0, 0), (1, 0, 0, 0),
                    (0, 1, 0, 0),                          # hazard: A falls, B rises together (Y stays 1)
                    (1, 1, 0, 0), (0, 1, 0, 0),             # B holds Y while A falls
                    (0, 0, 0, 0)]),
}
PLATE = "ply0a"     # the plate of the first load tube (latch_sweep.loads naming), what an LV Y means on the next HV net


def params(key):
    """the cell's part values: DEFAULT plus the cell's own (NOR4_N16: Ra 10k)"""
    return {**DEFAULT, **CELLS[key].get('p', {})}


def triode_half(t, plate, grid, p):
    """6N16B: unit A is the gate triode (plate, grid), unit B the other gate of the sheet, idle."""
    return (f"XT{t} pt{t} {grid} 0 ptx{t} nb20 0 6N16B {p.get('MN', '')}\nVT{t} {plate} pt{t} 0\n"
            f"RTX{t} vcc ptx{t} {p['Ra']}\n")


def c1_of(p, kind):
    return {"g1": p['C1p'], "g3": p['C1g3'], "tri": p['C1g'], "fol": p['C1fol']}[kind]


def cell_net(c, ins, y, p):
    n = f"RA vcc {y} {p['Ra']}\n"
    if c['name'] == "A1OOI_N16J2":
        n += L.penta("1", y, ins['A'], ins['B'], p) + triode_half("1", y, ins['C'], p)
    elif c['name'] == "A2OOI_J2":
        n += L.penta("1", y, ins['A'], ins['B'], p) + L.penta("2", y, ins['C'], ins['D'], p)
    elif c['name'] == "OR4_N16":
        # plates on +150 V, cathodes tied on k (VK measures the cathode current), Rs || Cs -> Y -> Rk -> -50 V
        n = (f"XF1 vcc {ins['A']} kk vcc {ins['B']} kk 6N16B {p.get('MN', '')}\n"
             f"XF2 vcc {ins['C']} kk vcc {ins['D']} kk 6N16B {p.get('MN', '')}\n"
             f"VK kk k1 0\nRS k1 {y} {p['Rs']}\nCS k1 {y} {p['Cs']}\nRK {y} nb {p['Rk']}\n")
    else:   # NOR4_N16: two 6N16B, every plate on Y; VT<i> measure the triode currents
        n += (f"XT1 pt1 {ins['A']} 0 pt2 {ins['B']} 0 6N16B {p.get('MN', '')}\nVT1 {y} pt1 0\nVT2 {y} pt2 0\n"
              f"XT2 pt3 {ins['C']} 0 pt4 {ins['D']} 0 6N16B {p.get('MN', '')}\nVT3 {y} pt3 0\nVT4 {y} pt4 0\n")
    return n


def expect(c):
    return [c['f'](*s) for s in c['seq']]


def arcs(c):
    """(key, pin, in_dir, out_dir, t) for the first transition of each kind: one input changes, Y changes"""
    seq, y = c['seq'], expect(c); out, seen = [], set()
    for i in range(1, len(seq)):
        ch = [k for k in range(len(seq[i])) if seq[i][k] != seq[i - 1][k]]
        if len(ch) == 1 and y[i] != y[i - 1]:
            pin = c['pins'][ch[0]]
            others = "".join(str(seq[i][k]) for k in range(len(seq[i])) if k != ch[0])
            key = f"{pin.lower()}{'r' if seq[i][ch[0]] else 'f'}_{others}"
            if key not in seen:
                seen.add(key); out.append((key, pin, "rise" if seq[i][ch[0]] else "fall",
                                           "rise" if y[i] else "fall", i * T))
    return out


def hazards(c):
    """two inputs change together and Y should stay: 0 for the HV-output cells, 1 for OR4_N16 (LV output)"""
    seq, y = c['seq'], expect(c)
    keep = 1 if c.get('out') == "LV" else 0
    return [i for i in range(1, len(seq))
            if sum(a != b for a, b in zip(seq[i], seq[i - 1])) == 2 and y[i] == y[i - 1] == keep]


def meas_lines(c, nodes, y, yl, pl=None):
    """.meas lines (without the leading dot), shared with the KiCad testbench (aoi_tb.py): Y at the end of each
    state, the lowest input and output-net grids, the hazard maxima and one delay per arc.
    nodes: pin -> node of the DUT input. LV-output cells (OR4_N16): yl is not used; the delays run to Y = -5 V
    (input grid -5 V -> Y -5 V, the key) and to the load plate pl = 100 V (key + "p"); the hazard is the dip of Y
    and the peak of the load plate."""
    seq = c['seq']; stop = T * len(seq)
    if c.get('out') == "LV":
        m = [f"meas tran y{i} find v({y}) at={(i + 1) * T - 0.05:.3f}u" for i in range(len(seq))]
        m += [f"meas tran lp{i} find v({pl}) at={(i + 1) * T - 0.05:.3f}u" for i in range(len(seq))]
        for pin in c['pins']:
            m.append(f"meas tran {pin.lower()}min min v({nodes[pin]}) from=0.5u to={stop}u")
        m.append(f"meas tran ylmin min v({y}) from=0.5u to={stop}u")
        for i in hazards(c):
            m += [f"meas tran haz{i} min v({y}) from={i * T}u to={(i + 1) * T}u",
                  f"meas tran hzp{i} max v({pl}) from={i * T}u to={(i + 1) * T}u"]
        for key, pin, di, do, t in arcs(c):
            nd = "fall" if do == "rise" else "rise"
            m += [f"meas tran {key} trig v({nodes[pin]}) val=-5 {di}=1 td={t - 0.1:.2f}u targ v({y}) val=-5 {do}=1 td={t - 0.1:.2f}u",
                  f"meas tran {key}p trig v({nodes[pin]}) val=-5 {di}=1 td={t - 0.1:.2f}u targ v({pl}) val=100 {nd}=1 td={t - 0.1:.2f}u"]
        return m
    m = [f"meas tran y{i} find v({y}) at={(i + 1) * T - 0.05:.3f}u" for i in range(len(seq))]
    for pin in c['pins']:
        m.append(f"meas tran {pin.lower()}min min v({nodes[pin]}) from=0.5u to={stop}u")
    m.append(f"meas tran ylmin min v({yl}) from=0.5u to={stop}u")
    for i in hazards(c):
        m.append(f"meas tran haz{i} max v({y}) from={i * T}u to={(i + 1) * T}u")
    for key, pin, di, do, t in arcs(c):
        m.append(f"meas tran {key} trig v({nodes[pin]}) val=-5 {di}=1 td={t - 0.1:.2f}u "
                 f"targ v({y}) val=100 {do}=1 td={t - 0.1:.2f}u")
    return m


def deck(c, p, ngrid):
    seq = c['seq']; stop = T * len(seq)
    s = f"* {c['name']} sweep\n.include {LIBS}/6Zh2B.sub\n.include {LIBS}/6N16B.sub\n"
    s += "VCC vcc 0 150\nVNB nb 0 -50\nVNB20 nb20 0 -20\n"
    ins = {}
    for k, pin in enumerate(c['pins']):
        node = pin.lower()
        ins[pin] = node
        s += L.driver(pin.lower(), [st[k] for st in seq], node, p, c1_of(p, c['grid'][pin]))
    s += cell_net(c, ins, "y", p)
    if c.get('out') == "LV":
        s += L.loads("y", p, ngrid, "y")
        m = meas_lines(c, {pin: pin.lower() for pin in c['pins']}, "y", None, PLATE)
        m.append(f"meas tran ikmax max i(VK) from=0.5u to={stop}u")
    else:
        s += L.div("y", "y", "yl", p, p['C1g'] * ngrid) + L.loads("yl", p, ngrid, "y")
        m = meas_lines(c, {pin: pin.lower() for pin in c['pins']}, "y", "yl")
    # cathode and screen currents of the 6Zh2B, worst over the run
    if c['name'] not in ("NOR4_N16", "OR4_N16"):
        for t in (["1"] if c['name'] == "A1OOI_N16J2" else ["1", "2"]):
            m.append(f"meas tran ipmax{t} max i(VP{t}) from=0.5u to={stop}u")
    s += f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(m) + "\n.endc\n.end\n"
    return s


def run(arg):
    key, p, n = arg
    c = CELLS[key]
    fn = os.path.join(tempfile.gettempdir(), f"aoi_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(c, p, n))
    o = subprocess.run([sys.executable, NGRUN, fn], capture_output=True, text=True).stdout
    return key, p.get('_name', ''), n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def fmt_lv(key, name, n, m):
    c = CELLS[key]; y = expect(c)
    g = lambda k, s=1: m.get(k, float('nan')) * s
    hi = [g(f"y{i}") for i, e in enumerate(y) if e]; lo = [g(f"y{i}") for i, e in enumerate(y) if not e]
    lph = max(g(f"lp{i}") for i, e in enumerate(y) if e); lpl = min(g(f"lp{i}") for i, e in enumerate(y) if not e)
    ar = arcs(c)
    up = [g(k, 1e9) for k, *_, do, _ in ar if do == "rise"]; dn = [g(k, 1e9) for k, *_, do, _ in ar if do == "fall"]
    upp = [g(k + "p", 1e9) for k, *_, do, _ in ar if do == "rise"]; dnp = [g(k + "p", 1e9) for k, *_, do, _ in ar if do == "fall"]
    hz = hazards(c)
    grids = " ".join(f"{p}{g(p.lower() + 'min'):5.1f}" for p in c['pins'])
    return (f"{c['name']:12s} {name:14s} N={n:2d} | Y 1 {min(hi):5.2f}..{max(hi):5.2f} 0 {min(lo):6.1f}..{max(lo):6.1f}"
            f" | load plate on 1 <= {lph:5.1f} on 0 >= {lpl:5.1f} | hazard Y {min(g(f'haz{i}') for i in hz):5.2f}"
            f" plate {max(g(f'hzp{i}') for i in hz):5.1f} | min {grids} | Ik {g('ikmax', 1e3):4.1f} mA"
            f" | LV->LV up {min(up):3.0f}..{max(up):3.0f} down {min(dn):3.0f}..{max(dn):3.0f}"
            f" | ->load plate up {min(upp):3.0f}..{max(upp):3.0f} down {min(dnp):3.0f}..{max(dnp):3.0f} ns")


def fmt(key, name, n, m):
    if CELLS[key].get('out') == "LV": return fmt_lv(key, name, n, m)
    c = CELLS[key]; y = expect(c)
    g = lambda k, s=1: m.get(k, float('nan')) * s
    ys = [g(f"y{i}") for i in range(len(y))]
    hi = [v for v, e in zip(ys, y) if e]; lo = [v for v, e in zip(ys, y) if not e]
    ar = arcs(c)
    rise = [g(k, 1e9) for k, *_, do, _ in ar if do == "rise"]
    fall = [g(k, 1e9) for k, *_, do, _ in ar if do == "fall"]
    hz = [g(f"haz{i}") for i in hazards(c)]
    worst = max(ar, key=lambda a: g(a[0]))
    grids = " ".join(f"{p}{g(p.lower() + 'min'):5.1f}" for p in c['pins'])
    return (f"{c['name']:12s} {name:14s} N={n:2d} | VOH {min(hi):5.1f} VOL {min(lo):4.1f}..{max(lo):4.1f}"
            f" haz {max(hz) if hz else float('nan'):5.1f} | min {grids} yl {g('ylmin'):5.1f}"
            f" | tpHL {min(fall):4.0f}..{max(fall):4.0f} tpLH {min(rise):4.0f}..{max(rise):4.0f} ns"
            f" (worst {worst[0]} {g(worst[0], 1e9):.0f})")


def detail(key, name, n, m):
    c = CELLS[key]
    return "  " + ", ".join(f"{k} {m.get(k, float('nan')) * 1e9:.0f}" for k, *_ in arcs(c))


if __name__ == "__main__":
    args = sys.argv[1:]
    grids = (2, 4, 6, 8, 10)
    if "--grids" in args:
        i = args.index("--grids"); grids = tuple(int(x) for x in args[i + 1].split(",")); del args[i:i + 2]
    keys = [a for a in args if a in CELLS] or list(CELLS)
    files = [a for a in args if a not in CELLS]
    CASES = [("nominal", {})]
    for f in files: exec(open(f).read())
    jobs = [(k, {**params(k), **ov, '_name': nm}, n) for k in keys for nm, ov in CASES for n in grids]
    with Pool(8) as pool:
        for r in pool.map(run, jobs):
            print(fmt(*r)); print(detail(*r))
