#!/usr/bin/env python3
"""BUF_N16 / OR2_N16 transient sweep over fanout (sch/logic/BUF_N16/README.md).
Both cells are cathode followers on the 6N16B (owner, 2026-10-28): plate straight to +150 V, the cathode resistor
to -50 V split into Rs (cathode -> Y, bypassed by Cs) and Rk (Y -> -50 V). LV grid input (1 = +10, 0 = -20 V)
from its own HV->LV divider; LV output Y straight onto the load grids, no divider on the output net.
  BUF_N16: one 6N16B = two independent followers A1 -> Y1, A2 -> Y2, each with its own Rs, Cs, Rk.
  OR2_N16: one 6N16B, cathodes tied, one Rs, Cs, Rk: the cathode follows the higher grid, Y = A | B.
Rs shifts Y about 5 V below the cathode, so "0" lands near -19 V although the cathode sits 5 V above its grid,
and it limits the current the load grids draw on a "1" (Ik, Pa). Cs (100 pF) passes the edges.
Chain: ideal HV pulse -> divider -> driver NOT (6N16B, Ra 10k) -> divider (C1 = C1g per DUT grid) -> DUT
grid; DUT output -> N load grids (N/2 NOT_N16 load tubes, both halves on the net) whose plates show what
the LV level means on the HV side.
usage: cf_sweep.py [BUF|OR2] [cases.py]; a cases file defines CASES = [(name, params), ...] and GRIDS.
Optional parameters: M (extra model parameters, e.g. "MU=20.8"), Rp (a plate resistor, rejected option)."""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6N16B.sub")
# input sequences, 2 us per state
SEQ = {
    # BUF: every edge of one input happens while the other one is static (crosstalk through Ca1a2)
    "BUF": ([0, 1, 1, 0, 0], [0, 0, 1, 1, 0]),
    # OR2: A up/down alone, B up/down alone, both up together, B down with A held (Y stays 1),
    # A down + B up together (hazard), B down alone
    "OR2": ([0, 1, 0, 0, 0, 1, 1, 0, 0], [0, 0, 0, 1, 0, 1, 0, 1, 0]),
}
# chosen values (sch/logic/BUF_N16/README.md): plate straight to +150 V, Rs 2.2k || Cs 100p, Rk 12k; C1 2.7 pF per follower grid
DEFAULT = dict(R1="470k", R2="200k", C1g=2.7, Rp=None, Rs="2.2k", Cs="100p", Rk="12k")


def drv(t, ga, gb, p):
    """driver tube: two NOT_N16 inverters, plates p{t}a / p{t}b, Ra 10k each"""
    return f"X{t} p{t}a {ga} 0 p{t}b {gb} 0 6N16B {p.get('M', '')}\nRA{t}a vcc p{t}a 10k\nRA{t}b vcc p{t}b 10k\n"


def div(t, hv, lv, p, c1):
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {c1}p\nR2{t} {lv} nb {p['R2']}\n"


def dut(cell, a, b, ya, yb, p):
    """the cell under test. Each follower: plate -> +150 V (or through Rp if one is given, for the rejected options);
    cathode -> VK (0 V, measures Ik) -> Rs || Cs -> output -> Rk -> -50 V.
    OR2: both triodes share Rs, Cs, Rk (cathodes tied)."""
    M = p.get('M', '')
    def stage(x, y):
        cs = f"CS{x} k{x}1 {y} {p['Cs']}\n" if p.get('Cs') else ""
        rp = f"RP{x} vcc pp{x} {p['Rp']}\n" if p.get('Rp') else ""
        return f"{rp}VK{x} k{x} k{x}1 0\nRS{x} k{x}1 {y} {p['Rs']}\n{cs}RK{x} {y} nb {p['Rk']}\n"
    pa = "ppa" if p.get('Rp') else "vcc"
    pb = "ppb" if p.get('Rp') and cell == "BUF" else pa
    if cell == "BUF":
        return f"XX {pa} {a} ka {pb} {b} kb 6N16B {M}\n" + stage('a', ya) + stage('b', yb)
    return f"XX {pa} {a} ka {pa} {b} ka 6N16B {M}\n" + stage('a', ya) + "VKb kb 0 0\n"


def loads(net, n, tag, p):
    """n grids on net: n/2 NOT_N16 tubes with both halves on the net; plate of the first one = pl{tag}"""
    s = ""
    for i in range(n // 2):
        pa = f"pl{tag}" if i == 0 else f"pl{tag}{i}a"
        s += (f"XL{tag}{i} {pa} {net} 0 pl{tag}{i}b {net} 0 6N16B {p.get('M', '')}\n"
              f"RL{tag}{i}a vcc {pa} 10k\nRL{tag}{i}b vcc pl{tag}{i}b 10k\n")
    return s


def pwl(bits, lo, hi):
    pts = []; t = 0
    for b in bits:
        v = hi if b else lo
        pts += [f"{t+20e-9:.3e} {v}", f"{t+2e-6:.3e} {v}"]; t += 2e-6
    return "PWL(0 %s %s)" % ((hi if bits[0] else lo), " ".join(pts))


def edges(seq):
    """(time in us, rise?) of every edge of one input"""
    return [(2 * i, seq[i] > seq[i - 1]) for i in range(1, len(seq)) if seq[i] != seq[i - 1]]


def meas_lines(cell, a, b, ya, yb, pla, plb, stop, pda="pda", ik=True):
    """.meas lines (no leading dot), shared with the KiCad testbench.
    Levels at the end of each state, grid / output minima, delays LV in -> LV out (-5 V on both) and
    LV in -> load plate (100 V, i.e. through one load stage), cathode current maxima."""
    sa, sb = SEQ[cell]
    n = len(sa)
    L = [f"meas tran ya{i} find v({ya}) at={2*i+1.95}u" for i in range(n)]
    L += [f"meas tran pa{i} find v({pla}) at={2*i+1.95}u" for i in range(n)]
    if cell == "BUF":
        L += [f"meas tran yb{i} find v({yb}) at={2*i+1.95}u" for i in range(n)]
    L += [f"meas tran ga{i} find v({a}) at={2*i+1.95}u" for i in range(n)]
    L += [f"meas tran {nm}min min v({x}) from=0.5u to={stop}u" for nm, x in (("a", a), ("b", b), ("y", ya))]
    if cell == "BUF":
        L += [f"meas tran ybmin min v({yb}) from=0.5u to={stop}u"]
    # cathode current (i(VK) is positive from the cathode into the output net)
    if ik:
        L += ["meas tran ika max i(vka) from=0.5u to=%gu" % stop, "meas tran ikb max i(vkb) from=0.5u to=%gu" % stop]
    # delays on the single-input arcs that switch the output
    arcs = []
    if cell == "BUF":
        arcs = [("a", a, ya, pla, t, r) for t, r in edges(sa)] + [("b", b, yb, plb, t, r) for t, r in edges(sb)]
    else:
        y = [x | z for x, z in zip(sa, sb)]
        for i in range(1, n):
            if y[i] == y[i - 1] or (sa[i] != sa[i - 1] and sb[i] != sb[i - 1]):
                continue
            nm, g = ("a", a) if sa[i] != sa[i - 1] else ("b", b)
            arcs.append((nm, g, ya, pla, 2 * i, y[i] > y[i - 1]))
    # the input divider: driver plate (100 V) -> DUT grid (-5 V), first rise and fall of A
    (tr, _), (tf, _) = [e for e in edges(sa) if e[1]][0], [e for e in edges(sa) if not e[1]][0]
    L += [f"meas tran tdiv_r trig v({pda}) val=100 rise=1 td={tr-0.1}u targ v({a}) val=-5 rise=1 td={tr-0.1}u",
          f"meas tran tdiv_f trig v({pda}) val=100 fall=1 td={tf-0.1}u targ v({a}) val=-5 fall=1 td={tf-0.1}u"]
    if cell == "OR2":
        # hazard A down + B up together at 14 us: Y must stay "1"; how deep it dips, how high the load plate goes,
        # and how long until the load plate is back below 80 V
        L += [f"meas tran hz_y min v({ya}) from=14u to=16u", f"meas tran hz_lp max v({pla}) from=14u to=16u",
              f"meas tran hz_t when v({pla})=80 fall=last from=14u to=16u"]
    for nm, g, y, pl, t, r in arcs:
        e, ne = ("rise", "fall") if r else ("fall", "rise")
        k = f"{'lh' if r else 'hl'}_{nm}{t}"
        L += [f"meas tran tp{k} trig v({g}) val=-5 {e}=1 td={t-0.1}u targ v({y}) val=-5 {e}=1 td={t-0.1}u",
              f"meas tran tq{k} trig v({g}) val=-5 {e}=1 td={t-0.1}u targ v({pl}) val=100 {ne}=1 td={t-0.1}u"]
    return L


def deck(cell, p, ngrid):
    sa, sb = SEQ[cell]
    inv = lambda bits: [1 - x for x in bits]           # the driver inverts
    stop = 2 * len(sa)
    s = f"""* {cell}_N16 sweep
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
VSA sa 0 {pwl(inv(sa), 50, 150)}
VSB sb 0 {pwl(inv(sb), 50, 150)}
"""
    s += div('sa', 'sa', 'ia', p, 3.9) + div('sb', 'sb', 'ib', p, 3.9)
    s += drv('d', 'ia', 'ib', p) + div('da', 'pda', 'a', p, p['C1g']) + div('db', 'pdb', 'b', p, p['C1g'])
    s += dut(cell, 'a', 'b', 'ya', 'yb', p)
    s += loads('ya', ngrid, 'a', p)
    if cell == "BUF":
        s += loads('yb', ngrid, 'b', p)
    s += f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(meas_lines(cell, "a", "b", "ya", "yb", "pla", "plb", stop))
    s += f"\nmeas tran icc avg i(VCC) from=0 to={stop}u\n.endc\n.end\n"
    return s


def run(arg):
    cell, name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"cf_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(cell, p, n))
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout
    return cell, name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def fmt(cell, name, n, m):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    sa, sb = SEQ[cell]
    y = sa if cell == "BUF" else [x | z for x, z in zip(sa, sb)]
    hi = [g(f"ya{i}") for i in range(len(y)) if y[i]] + ([g(f"yb{i}") for i in range(len(sb)) if sb[i]] if cell == "BUF" else [])
    lo = [g(f"ya{i}") for i in range(len(y)) if not y[i]] + ([g(f"yb{i}") for i in range(len(sb)) if not sb[i]] if cell == "BUF" else [])
    plo = [g(f"pa{i}") for i in range(len(y)) if y[i]]
    phi = [g(f"pa{i}") for i in range(len(y)) if not y[i]]
    gin = [g(f"ga{i}") for i in range(len(sa))]
    tp = {k: v * 1e9 for k, v in m.items() if k.startswith(("tp", "tq"))}
    mx = lambda pre: max([v for k, v in tp.items() if k.startswith(pre)] or [float('nan')])
    return (f"{cell} {name:14s} N={n:2d} | Y1 {min(hi):5.2f}..{max(hi):5.2f} Y0 {min(lo):6.1f}..{max(lo):6.1f}"
            f" | load plate 0:{max(plo):5.1f} 1:{min(phi):5.1f} | DUT grid {min(gin):5.1f}..{max(gin):5.2f}"
            f" min a {g('amin'):5.1f} b {g('bmin'):5.1f} y {g('ymin'):5.1f}"
            f" | Ik {max(g('ika'), g('ikb'))*1e3:4.1f} mA"
            + (f" | hazard Y {g('hz_y'):5.2f} LP {g('hz_lp'):5.1f} back<80V {(g('hz_t')-14e-6)*1e9:4.0f} ns" if cell == "OR2" else "")
            + f" | div r/f {g('tdiv_r',1e9):3.0f}/{g('tdiv_f',1e9):3.0f}"
            f" | LV->LV hl {mx('tphl'):3.0f} lh {mx('tplh'):3.0f} | ->load plate hl {mx('tqhl'):3.0f} lh {mx('tqlh'):3.0f} ns")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a in SEQ]
    files = [a for a in sys.argv[1:] if a not in SEQ]
    CELLS = args or ["BUF", "OR2"]
    CASES = [("default", dict(DEFAULT))]
    GRIDS = (2, 4, 6, 8, 10)
    if files: exec(open(files[0]).read())
    jobs = [(c, nm, p, n) for c in CELLS for nm, p in CASES for n in GRIDS]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
