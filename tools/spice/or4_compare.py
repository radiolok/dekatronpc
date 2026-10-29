#!/usr/bin/env python3
"""OR4: cathode followers (OR4_N16, two 6N16B) against diode OR (OR4_N16X7, 2 x 6Kh7B + half a 6N16B).
The owner asked for the comparison before choosing (2026-10-29).

Common chain: ideal HV pulse -> divider -> driver NOT (6N16B, Ra 10k: plate pd<x>) -> the cell's input network ->
the cell -> Y (LV) -> N load grids (NOT_N16 loads; their plate pl shows what Y means on the next HV net).
  A     OR4_N16:    each driver plate -> its own divider (C1 2.7 pF) -> one follower grid; four triodes, cathodes
                    tied, Rs 2.2k || Cs 100p -> Y -> Rk -> -50 V (OR2_N16 widened).
  B-HV  OR4_N16X7:  each driver plate -> diode (6Kh7B, anode on the plate) -> node N; Rd from N to -50 V;
                    N -> one divider (C1 2.7 pF) -> the grid of one follower (half a 6N16B), Rs || Cs, Rk.
  B-LV  OR4_N16X7:  each driver plate -> its own divider (C1 3.9 pF) -> diode -> node N = the follower grid;
                    Rd from N to -50 V.
Delays: driver plate crossing 100 V -> load plate crossing 100 V (the cell with its input network and one load
stage), first rise and fall of every input alone. Driver "1": the lowest high plate of a driver (the diode load).

usage: or4_compare.py [grids ...]
"""
import os, re, subprocess, sys, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cf_sweep as CF   # noqa: E402

LIBS = os.path.join(HERE, "..", "..", "sch", "libs")
P = dict(CF.DEFAULT)
SEQ = [(0, 0, 0, 0), (1, 0, 0, 0), (0, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 0),
       (0, 0, 0, 1), (0, 0, 0, 0), (1, 1, 1, 1), (0, 0, 0, 0), (1, 0, 0, 0),
       (0, 1, 0, 0),                    # hazard: A falls, B rises together (Y stays 1)
       (0, 0, 0, 0)]
PINS = "abcd"
VARIANTS = [("A follower", dict(kind="A")),
            ("A follower Rk 10k", dict(kind="A", Rk="10k")),
            ("B-HV Rd 470k", dict(kind="BHV", Rd="470k")), ("B-HV Rd 150k", dict(kind="BHV", Rd="150k")),
            ("B-HV Rd 47k", dict(kind="BHV", Rd="47k")),
            ("B-LV Rd 470k", dict(kind="BLV", Rd="470k")), ("B-LV Rd 150k", dict(kind="BLV", Rd="150k"))]


def follower(x, grid, y, p, M=""):
    return (f"XF{x} vcc {grid} kf{x} vcc nb20 kfx{x} 6N16B {M}\nRS{x} kf{x} {y} {p['Rs']}\nCS{x} kf{x} {y} {p['Cs']}\n"
            f"RK{x} {y} nb {p['Rk']}\nRKX{x} kfx{x} nb 12k\n")


def deck(p, ngrid):
    stop = 2 * len(SEQ)
    s = (f"* OR4 compare {p['kind']}\n.include {LIBS}/6N16B.sub\n.include {LIBS}/6Kh7B.sub\n"
         "VCC vcc 0 150\nVNB nb 0 -50\nVNB20 nb20 0 -20\n")
    for k, x in enumerate(PINS):
        bits = [st[k] for st in SEQ]
        s += f"VS{x} s{x} 0 {CF.pwl([1 - b for b in bits], 50, 150)}\n" + CF.div(f"s{x}", f"s{x}", f"i{x}", p, 3.9)
        s += f"XD{x} pd{x} i{x} 0 pdx{x} nb 0 6N16B\nRD{x} vcc pd{x} 10k\nRDX{x} vcc pdx{x} 10k\n"
    if p['kind'] == "A":
        for x in PINS: s += CF.div(f"g{x}", f"pd{x}", f"g{x}", p, 2.7)
        s += ("XF1 vcc ga k vcc gb k 6N16B\nXF2 vcc gc k vcc gd k 6N16B\n"
              f"RS k y {p['Rs']}\nCS k y {p['Cs']}\nRK y nb {p['Rk']}\n")
    elif p['kind'] == "BHV":
        for x in PINS: s += f"XK{x} pd{x} n 6Kh7B\n"
        s += f"RD n nb {p['Rd']}\n" + CF.div("n", "n", "g", p, 2.7) + follower("1", "g", "y", p)
    else:
        for x in PINS: s += CF.div(f"g{x}", f"pd{x}", f"g{x}", p, 3.9) + f"XK{x} g{x} n 6Kh7B\n"
        s += f"RD n nb {p['Rd']}\n" + follower("1", "n", "y", p)
    s += CF.loads("y", ngrid, "a", p)
    m = [f"meas tran y{i} find v(y) at={2*i+1.95}u" for i in range(len(SEQ))]
    m += [f"meas tran lp{i} find v(pla) at={2*i+1.95}u" for i in range(len(SEQ))]
    m += [f"meas tran dmin{x} min v(pd{x}) from={2*SEQ.index(next(st for st in SEQ if st[k]))+1.0}u "
          f"to={2*SEQ.index(next(st for st in SEQ if st[k]))+1.95}u" for k, x in enumerate(PINS)]
    m += ["meas tran hz max v(pla) from=24u to=26u", f"meas tran ymin min v(y) from=0.5u to={stop}u"]
    for k, x in enumerate(PINS):
        i = next(i for i, st in enumerate(SEQ) if st[k])
        # driver plate rises when the bit rises (the driver inverts its HV source); the load plate falls
        m.append(f"meas tran r{x} trig v(pd{x}) val=100 rise=1 td={2*i-0.1}u targ v(pla) val=100 fall=1 td={2*i-0.1}u")
        m.append(f"meas tran f{x} trig v(pd{x}) val=100 fall=1 td={2*i+1.9}u targ v(pla) val=100 rise=1 td={2*i+1.9}u")
    m.append(f"meas tran icc avg i(VCC) from=0 to={stop}u")
    return s + f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(m) + "\n.endc\n.end\n"


def run(arg):
    name, ov, n = arg
    p = {**P, **ov}
    fn = os.path.join(tempfile.gettempdir(), f"or4cmp_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n))
    o = subprocess.run([sys.executable, CF.NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def fmt(name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    y = [1 if any(st) else 0 for st in SEQ]
    yh = [g(f"y{i}") for i in range(len(SEQ)) if y[i]]; yl = [g(f"y{i}") for i in range(len(SEQ)) if not y[i]]
    lph = max(g(f"lp{i}") for i in range(len(SEQ)) if y[i])       # load plate when Y = 1 (should be low)
    lpl = min(g(f"lp{i}") for i in range(len(SEQ)) if not y[i])
    r = [g(f"r{x}", 1e9) for x in PINS]; f = [g(f"f{x}", 1e9) for x in PINS]
    return (f"{name:18s} N={n:2d} | Y 1: {min(yh):5.2f}..{max(yh):5.2f} 0: {min(yl):6.1f}..{max(yl):6.1f}"
            f" | load plate on 1 <= {lph:5.1f} on 0 >= {lpl:5.1f} | driver '1' >= {min(g('dmin' + x) for x in PINS):5.1f} V"
            f" | in rise -> load {min(r):4.0f}..{max(r):4.0f} ns, in fall -> load {min(f):5.0f}..{max(f):5.0f} ns"
            f" | hazard load plate {g('hz'):5.1f} | Icc {-g('icc', 1e3):4.1f} mA")


if __name__ == "__main__":
    grids = [int(x) for x in sys.argv[1:]] or [2, 6, 10]
    jobs = [(nm, ov, n) for nm, ov in VARIANTS for n in grids]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
