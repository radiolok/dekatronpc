#!/usr/bin/env python3
"""Gated RS latch RSLATCH_J2N16 transient sweep over fanout (sch/logic/RSLATCH_J2N16/README.md).

Cell: two AND-OR-INVERT halves on a common plate each, cross-coupled:
    QN = ~((S & E) | Q)      pentode 6Zh2B #1 (AND of S, E) + triode A of a 6N16B (grid from Q)
    Q  = ~((R & E) | QN)     pentode 6Zh2B #2 (AND of R, E) + triode B of the same 6N16B (grid from QN)
Levels as REQ-MOD-012: LV inputs on grids (1 = +10, 0 = -20 V), HV outputs on plates (1 = +150, 0 = +50 V).
Each output plate drives its cross triode through an HV->LV divider. fb = "int": a divider inside the cell
(C1 = C1g, one grid), the output pin is HV and the net outside gets its own divider (one per net, as for any cell).
fb = "net": the net divider of the output feeds the cross triode too (C1 = C1g x (1 + grids)).
eg = "g3": E on g3 of both pentodes (Cb on each g3), S/R on g1; eg = "g1": E on g1, S/R on g3.
Chain: ideal HV pulse -> divider -> driver (6N16B triode, Ra 10k) -> divider -> DUT input;
Q and QN -> divider (C1 = C1g x grids) -> N triode grids (N/2 load 6N16B tubes, both halves on the net).
States (S,R,E), 2 us each, see SEQ. Delays: input crossing -5 V (LV) to output crossing 100 V (HV).

Divider C1 per grid: C1g triode grid, C1p pentode g1 grid (default C1g), C1g3 pentode g3 grid, C1f the in-cell
feedback divider (fb = "int").
Optional parameters: M (6Zh2B instance parameters, e.g. "CG3A=2.5P"), MN (6N16B).
"""
import subprocess, re, sys, os, tempfile
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
LIBS = os.path.join(HERE, "..", "..", "sch", "libs")
# (S, R, E) per 2 us state
SEQ = [(0, 1, 1),   # 0 reset, start-up
       (0, 0, 0),   # 1 hold
       (1, 0, 0),   # 2 S rises while closed: no change
       (1, 0, 1),   # 3 E rises: set
       (1, 0, 0),   # 4 E falls: hold
       (0, 1, 0),   # 5 S and R swap while closed: no change
       (0, 1, 1),   # 6 E rises: reset
       (0, 0, 1),   # 7 R falls while open: hold
       (1, 0, 1),   # 8 S rises while open: set
       (0, 0, 1),   # 9 S falls: hold
       (0, 1, 1),   # 10 R rises while open: reset
       (0, 0, 0)]   # 11
T = 2.0  # us per state


def model_q(seq, q=0):
    """reference behaviour: Q after each state"""
    out = []
    for s, r, e in seq:
        if e and s and not r: q = 1
        elif e and r and not s: q = 0
        out.append(q)
    return out


def penta(t, plate, g1, g3, p):
    """6Zh2B with g1, g3 inputs; VP<t> measures its plate current, the screen node is s<t>"""
    s = (f"XJ{t} pp{t} {g3} s{t} 0 {g1} 6Zh2B {p.get('M', '')}\nVP{t} {plate} pp{t} 0\n"
         f"RS{t} vcc s{t} {p['Rg2']}\n")
    if p.get('Cb'): s += f"CB{t} {g3} nb {p['Cb']}p\n"
    return s


def div(t, hv, lv, p, c1):
    return f"R1{t} {hv} {lv} {p['R1']}\nC1{t} {hv} {lv} {c1}p\nR2{t} {lv} nb {p['R2']}\n"


def rslatch(t, s_, r_, e_, q, qn, p, ext=0):
    """the cell; q, qn are the HV output nodes. Returns (netlist, LV node of q, LV node of qn) where the
    LV nodes are the cross-triode grids. ext = grids on each output net outside the cell (for fb='net')."""
    g = lambda a, b: (a, b) if p['eg'] == 'g3' else (b, a)   # (g1, g3) of a pentode with data a, enable b
    s1, s3 = g(s_, e_); r1, r3 = g(r_, e_)
    n = penta(f"{t}s", qn, s1, s3, p) + penta(f"{t}r", q, r1, r3, p)
    n += f"RA{t}q vcc {q} {p['Ra']}\nRA{t}n vcc {qn} {p['Ra']}\n"
    if p['fb'] == 'int':
        lq, lqn = f"fq{t}", f"fqn{t}"
        n += div(f"{t}q", q, lq, p, p['C1f']) + div(f"{t}n", qn, lqn, p, p['C1f'])
    else:
        lq, lqn = f"lq{t}", f"lqn{t}"
        n += div(f"{t}q", q, lq, p, p['C1g'] * (1 + ext)) + div(f"{t}n", qn, lqn, p, p['C1g'] * (1 + ext))
    n += f"XN{t} pt{t}a {lq} 0 pt{t}b {lqn} 0 6N16B {p.get('MN', '')}\nVT{t}a {qn} pt{t}a 0\nVT{t}b {q} pt{t}b 0\n"
    return n, lq, lqn


def pwl(bits, lo, hi, t0=0.0):
    pts = []; t = 0
    for b in bits:
        v = hi if b else lo
        pts += [f"{(t+0.02)*1e-6:.4e} {v}", f"{(t+T)*1e-6:.4e} {v}"]; t += T
    return "PWL(0 %s %s)" % ((hi if bits[0] else lo), " ".join(pts))


def driver(t, bits, lv, p, c1):
    """ideal HV pulse -> divider -> one 6N16B triode (Ra 10k) -> divider (c1) -> lv"""
    inv = [1 - b for b in bits]
    return (f"VS{t} hs{t} 0 {pwl(inv, 50, 150)}\n" + div(f"s{t}", f"hs{t}", f"is{t}", p, p['C1g'])
            + f"XD{t} pd{t} is{t} 0 pdx{t} nb 0 6N16B\nRD{t} vcc pd{t} 10k\nRDX{t} vcc pdx{t} 10k\n"
            + div(f"d{t}", f"pd{t}", lv, p, c1))


def c1_in(p, kind):
    """divider C1 of a DUT input net: S/R drive one grid, E two (both pentodes)"""
    g1, g3 = p.get('C1p', p['C1g']), p['C1g3']
    if kind == 'e': return 2 * (g3 if p['eg'] == 'g3' else g1)
    return g1 if p['eg'] == 'g3' else g3


def loads(lv, p, ngrid, tag):
    return "".join(f"XL{tag}{i} pl{tag}{i}a {lv} 0 pl{tag}{i}b {lv} 0 6N16B\n"
                   f"RL{tag}{i}a vcc pl{tag}{i}a 10k\nRL{tag}{i}b vcc pl{tag}{i}b 10k\n" for i in range(ngrid // 2))


def arcs(seq):
    """(name, input, in_dir, out_dir_of_Q, t) for each transition where one input changes and Q changes"""
    q = model_q(seq); out = []; seen = {}
    for i in range(1, len(seq)):
        ch = [k for k in range(3) if seq[i][k] != seq[i - 1][k]]
        if len(ch) == 1 and q[i] != q[i - 1]:
            k = ch[0]; nm = "sre"[k]
            d = "rise" if seq[i][k] else "fall"
            key = f"{nm}{'r' if d == 'rise' else 'f'}_q{'r' if q[i] else 'f'}"
            if key in seen: continue
            seen[key] = 1
            out.append((key, nm, d, "rise" if q[i] else "fall", i * T))
    return out


def meas_lines(seq, nodes, stop):
    """nodes: dict s, r, e (LV inputs), q, qn (HV outputs), lq, lqn (cross grids), yq (LV output net)"""
    L = [f"meas tran q{i} find v({nodes['q']}) at={i*T+T-0.05:.2f}u" for i in range(len(seq))]
    L += [f"meas tran n{i} find v({nodes['qn']}) at={i*T+T-0.05:.2f}u" for i in range(len(seq))]
    L += [f"meas tran {k}min min v({nodes[k]}) from=0.5u to={stop}u" for k in ("s", "r", "e", "lq", "lqn", "yq")]
    L += [f"meas tran {k}max max v({nodes[k]}) from=0.5u to={stop}u" for k in ("lq", "lqn")]
    L += [f"meas tran {k}lv find v({nodes[k]}) at={T-0.05}u" for k in ("lq", "lqn", "yq")]
    q = model_q(seq)
    for key, nm, d, qd, t in arcs(seq):
        nd = "fall" if qd == "rise" else "rise"
        td = f"td={t-0.1:.1f}u"
        L.append(f"meas tran {key} trig v({nodes[nm]}) val=-5 {d}=1 {td} targ v({nodes['q']}) val=100 {qd}=1 {td}")
        L.append(f"meas tran {key}n trig v({nodes[nm]}) val=-5 {d}=1 {td} targ v({nodes['qn']}) val=100 {nd}=1 {td}")
    # glitches on Q / QN in states where nothing should change
    for i in range(1, len(seq)):
        if q[i] == q[i - 1]:
            f = "max" if q[i] == 0 else "min"
            L.append(f"meas tran gq{i} {f} v({nodes['q']}) from={i*T+0.05:.2f}u to={i*T+T:.2f}u")
            L.append(f"meas tran gn{i} {'min' if f == 'max' else 'max'} v({nodes['qn']}) from={i*T+0.05:.2f}u to={i*T+T:.2f}u")
    return L


def deck(p, ngrid, seq=SEQ, extra=""):
    stop = T * len(seq)
    s = f"* RSLATCH_J2N16 sweep\n.include {LIBS}/6Zh2B.sub\n.include {LIBS}/6N16B.sub\nVCC vcc 0 150\nVNB nb 0 -50\n"
    s += driver("s", [x[0] for x in seq], "s", p, c1_in(p, 's'))
    s += driver("r", [x[1] for x in seq], "r", p, c1_in(p, 'r'))
    s += driver("e", [x[2] for x in seq], "e", p, c1_in(p, 'e'))
    cell, lq, lqn = rslatch("x", "s", "r", "e", "q", "qn", p, ext=ngrid)
    s += cell
    if p['fb'] == 'int':
        s += div("yq", "q", "yq", p, p['C1g'] * ngrid) + div("yn", "qn", "yn", p, p['C1g'] * ngrid)
        yq, yn = "yq", "yn"
    else:
        yq, yn = lq, lqn
    s += loads(yq, p, ngrid, "q") + loads(yn, p, ngrid, "n")
    nodes = dict(s="s", r="r", e="e", q="q", qn="qn", lq=lq, lqn=lqn, yq=yq)
    s += f".tran 5n {stop}u\n.control\nrun\n" + "\n".join(meas_lines(seq, nodes, stop))
    s += f"\nmeas tran icc avg i(VCC) from={T}u to={stop}u\n{extra}.endc\n.end\n"
    return s


def run(arg):
    name, p, n = arg
    fn = os.path.join(tempfile.gettempdir(), f"latch_sweep_{os.getpid()}.cir")
    open(fn, "w").write(deck(p, n))
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout
    return name, n, {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def fmt(name, n, m, seq=SEQ):
    g = lambda k, s=1: m.get(k, float('nan')) * s
    q = model_q(seq)
    hi = [g(f"q{i}") for i in range(len(seq)) if q[i]] + [g(f"n{i}") for i in range(len(seq)) if not q[i]]
    lo = [g(f"q{i}") for i in range(len(seq)) if not q[i]] + [g(f"n{i}") for i in range(len(seq)) if q[i]]
    vs = min(g("n2"), g("q5"))       # held high for >= 4 us: settled VOH
    ok = all(abs(x - (147 if b else 50)) < 45 for x, b in zip([g(f"q{i}") for i in range(len(seq))], q))
    gl_lo = max([g(f"gq{i}") for i in range(1, len(seq)) if f"gq{i}" in m and q[i] == 0]
                + [g(f"gn{i}") for i in range(1, len(seq)) if f"gn{i}" in m and q[i] == 1] or [float('nan')])
    gl_hi = min([g(f"gq{i}") for i in range(1, len(seq)) if f"gq{i}" in m and q[i] == 1]
                + [g(f"gn{i}") for i in range(1, len(seq)) if f"gn{i}" in m and q[i] == 0] or [float('nan')])
    d = " ".join(f"{k}={g(k,1e9):3.0f}/{g(k+'n',1e9):3.0f}" for k, *_ in arcs(seq))
    return (f"{name:22s} N={n:2d} {'OK ' if ok else 'BAD'} | VOH {vs:5.1f} ({min(hi):5.1f}) VOL {min(lo):4.1f}..{max(lo):4.1f}"
            f" glitch lo<{gl_lo:5.1f} hi>{gl_hi:5.1f} | min s {g('smin'):5.1f} r {g('rmin'):5.1f} e {g('emin'):5.1f}"
            f" fb {min(g('lqmin'), g('lqnmin')):5.1f}..{max(g('lqmax'), g('lqnmax')):4.1f} y {g('yqmin'):5.1f}"
            f" | Icc {-g('icc',1e3):4.1f} mA | Q/QN ns {d}")


BASE = dict(R1="470k", R2="200k", C1g=3.9, C1g3=6.8, C1f=3.9, Cb=15, Ra="15k", Rg2="15k", eg="g3", fb="int")
CHOSEN = dict(Ra="10k", C1p=2.7)

if __name__ == "__main__":
    # usage: latch_sweep.py [cases.py]; a cases file defines CASES = [(name, params), ...] and optionally GRIDS
    CASES = [("RSLATCH", dict(BASE, **CHOSEN))]
    GRIDS = (2, 4, 6, 8, 10)
    if len(sys.argv) > 1: exec(open(sys.argv[1]).read())
    jobs = [(nm, p, n) for nm, p in CASES for n in GRIDS]
    with Pool(8) as pool:
        for r in pool.map(run, jobs): print(fmt(*r))
