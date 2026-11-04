#!/usr/bin/env python3
"""DFFP2_J2N16 testbench, shared by the KiCad testbench (tools/kicad/gen_dffp_j2n16.py) and the plain-SPICE
reference run (sch/logic/DFFP2_J2N16/README.md, doc/tc_n5_pulse_dff.md).

The cell: two pulse-clocked D flip-flops (sheet DFFP_J2N16 each) and one 6N16B for both D inverters.
The bench: the two flip-flops as a shift register. FF1.D comes from a driver plate (HV), FF1.Q drives FF2.D and a
divider with 4 more grids, QN1, Q2, QN2 drive a divider with 6 grids each. Both C pins sit on one HV clock line
(an ideal 50 / 150 V source with 30 ns edges). D changes a quarter period after each rising clock edge.
Node names are the KiCad ones (/CK, /Q1, /DUT/FF1/G ...), so the .meas lines are the same in both runs.

The part values live here (CELL) and nowhere else; pff_sweep.P carries the same numbers for the sweeps.

usage: pff_tb.py            runs the plain-SPICE reference and prints the .meas values and the check
"""
import os, re, subprocess, sys, tempfile
import latch_sweep as L
import dff_sweep as D

CELL = dict(Ra="10k", La="1m", Rg2="12k",                 # plates and screens
            R1f="470k", C1f="3.9p", R2f="200k",           # feedback dividers (as RSLATCH_J2N16)
            R1s="150k", R2s="62k",                        # slow dividers to the pentode g1 (no C1: the delay)
            R1i="470k", C1i="3.9p", R2i="200k",           # D -> inverter grid
            Cc="3.9p", Rt="43k", Rb="130k",               # clock pulse network on g3: rest -12.4 V, Thevenin 32.3k
            Rinv="10k")                                   # inverter plate
PER = 2.0          # clock period, us
FAN = 6            # grids on each output net (Q1: FF2.D plus 4 grids)


def core(pre, d, dn, c, q, qn, x=CELL):
    """one flip-flop (sheet DFFP_J2N16): pre is the hierarchical prefix of its local nets"""
    n = lambda s: pre + s
    return (f"XJ{pre}1 {qn} {n('G')} {n('SG1')} 0 {n('S')} 6Zh2B\n"          # 6Zh2B: A G3 G2 K G1
            f"XJ{pre}2 {q} {n('G')} {n('SG2')} 0 {n('R')} 6Zh2B\n"
            f"XN{pre} {qn} {n('FQ')} 0 {q} {n('FQN')} 0 6N16B\n"            # 6N16B: Pa Ga Ka Pb Gb Kb
            f"RA{pre}1 vcc {n('RAQN')} {x['Ra']}\nLA{pre}1 {n('RAQN')} {qn} {x['La']}\n"
            f"RA{pre}2 vcc {n('RAQ')} {x['Ra']}\nLA{pre}2 {n('RAQ')} {q} {x['La']}\n"
            f"RG{pre}1 vcc {n('SG1')} {x['Rg2']}\nRG{pre}2 vcc {n('SG2')} {x['Rg2']}\n"
            f"R1{pre}q {q} {n('FQ')} {x['R1f']}\nC1{pre}q {q} {n('FQ')} {x['C1f']}\nR2{pre}q {n('FQ')} nb {x['R2f']}\n"
            f"R1{pre}n {qn} {n('FQN')} {x['R1f']}\nC1{pre}n {qn} {n('FQN')} {x['C1f']}\nR2{pre}n {n('FQN')} nb {x['R2f']}\n"
            f"R1{pre}s {d} {n('S')} {x['R1s']}\nR2{pre}s {n('S')} nb {x['R2s']}\n"
            f"R1{pre}r {dn} {n('R')} {x['R1s']}\nR2{pre}r {n('R')} nb {x['R2s']}\n"
            f"CC{pre} {c} {n('G')} {x['Cc']}\nRT{pre} {n('G')} 0 {x['Rt']}\nRB{pre} {n('G')} nb {x['Rb']}\n")


def dffp2(pre, d1, d2, c1, c2, q1, qn1, q2, qn2, x=CELL):
    """the cell sheet DFFP2_J2N16: the inverter tube, its two grid dividers and two cores"""
    n = lambda s: pre + s
    s = (f"XI{pre} {n('DN1')} {n('DI1')} 0 {n('DN2')} {n('DI2')} 0 6N16B\n"
         f"RI{pre}1 vcc {n('DN1')} {x['Rinv']}\nRI{pre}2 vcc {n('DN2')} {x['Rinv']}\n")
    for i, d in ((1, d1), (2, d2)):
        s += (f"R1{pre}i{i} {d} {n(f'DI{i}')} {x['R1i']}\nC1{pre}i{i} {d} {n(f'DI{i}')} {x['C1i']}\n"
              f"R2{pre}i{i} {n(f'DI{i}')} nb {x['R2i']}\n")
    s += core(n("FF1/"), d1, n("DN1"), c1, q1, qn1, x) + core(n("FF2/"), d2, n("DN2"), c2, q2, qn2, x)
    return s


def bench():
    """stimulus, outputs and .meas of DFFP2_J2N16_tb"""
    ct, cb, dt, db, samp, ref, stop = D.stimulus("dff", PER, 0.25, "pos")
    ref2 = [0] + ref[:-1]
    t3 = 3 * PER + 0.1
    meas = [f"meas tran q{k} find v(/Q1) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran n{k} find v(/QN1) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran p{k} find v(/Q2) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran m{k} find v(/QN2) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran {nm}min min v({x}) from=0.5u to={stop:.3f}u" for nm, x in
             (("g1", "/DUT/FF1/G"), ("g2", "/DUT/FF2/G"), ("s2", "/DUT/FF2/S"), ("r2", "/DUT/FF2/R"),
              ("fq2", "/DUT/FF2/FQ"), ("fqn2", "/DUT/FF2/FQN"), ("y", "/Q2_LV"))]
    meas += ["meas tran g1max max v(/DUT/FF1/G) from=0.5u to=%.3fu" % stop]
    meas += [f"meas tran pw trig v(/DUT/FF2/G) val=-5 rise=1 td={t3:.2f}u targ v(/DUT/FF2/G) val=-5 fall=1 td={t3:.2f}u"]
    # clock to Q at the first edge (period 3 on) where the output rises and where it falls
    for q, r in (("Q1", ref), ("Q2", ref2)):
        for d, want in (("r", (0, 1)), ("f", (1, 0))):
            k = next(k for k in range(3, len(r)) if (r[k - 1], r[k]) == want)
            te = k * PER + PER / 2 - 0.1
            meas.append(f"meas tran tcq_{q.lower()}{d} trig v(/CK) val=100 rise=1 td={te:.2f}u "
                        f"targ v(/{q}) val=100 {'rise' if d == 'r' else 'fall'}=1 td={te:.2f}u")
    return dict(name="DFFP2_J2N16", clock=(ct, cb), d=(dt, db), stop=stop, meas=meas, ref=ref, ref2=ref2, samp=samp,
                outputs={"Q1": FAN - 2, "QN1": FAN, "Q2": FAN, "QN2": FAN},
                note=f"Clock {PER} us (rising edge captures); FF1.Q -> FF2.D; D1 changes {PER/4} us after the edge.")


def clock_pts(ct, cb, tr=0.03):
    """(t_us, V) of the HV clock line: bit 1 = 150 V"""
    pts = [(0.0, 150 if cb[0] else 50)]
    for t, b, pb in zip(ct[1:], cb[1:], cb[:-1]):
        if b != pb: pts += [(t, 150 if pb else 50), (t + tr, 150 if b else 50)]
    return pts


def d_pts(dt, db):
    """(t_us, V) of the ideal source in front of the driver triode (it inverts): bit 1 -> 50 V"""
    v = lambda b: 50 if b else 150
    pts = [(0.0, v(db[0]))]
    for t, b, pb in zip(dt[1:], db[1:], db[:-1]):
        if b != pb: pts += [(t, v(pb)), (t + 0.02, v(b))]
    return pts


def deck(tb):
    p = dict(L.BASE, **L.CHOSEN)
    s = f"* {tb['name']} testbench, plain SPICE\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\n"
    s += "VCC vcc 0 150\nVNB nb 0 -50\n"
    s += "VSCK /CK 0 PWL(%s)\n" % " ".join(f"{t:.4f}u {v}" for t, v in clock_pts(*tb['clock']))
    s += "VSD /STIM_D 0 PWL(%s)\n" % " ".join(f"{t:.4f}u {v}" for t, v in d_pts(*tb['d']))
    s += L.div("sd", "/STIM_D", "/IS_D", p, p['C1g'])
    s += "XDD /D1 /IS_D 0 /PDX_D nb 0 6N16B\nRDD vcc /D1 10k\nRDXD vcc /PDX_D 10k\n"
    s += dffp2("/DUT/", "/D1", "/Q1", "/CK", "/CK", "/Q1", "/QN1", "/Q2", "/QN2")
    for o, ng in tb['outputs'].items():
        s += L.div(f"y{o}", f"/{o}", f"/{o}_LV", p, p['C1g'] * ng) + L.loads(f"/{o}_LV", p, ng, o)
    s += f".options method=gear\n.tran 5n {tb['stop']:.3f}u\n.control\nrun\n" + "\n".join(tb['meas']) + "\n.endc\n.end\n"
    return s


def check(tb, m):
    """sampled levels against the reference, valid for the next stage: "1" > 118 V, "0" < 92 V (from period 3 on)"""
    good = lambda v, b: v > 118 if b else v < 92
    bad = []
    for k in range(3, len(tb['ref'])):
        for a, an, r in (("q", "n", tb['ref'][k]), ("p", "m", tb['ref2'][k])):
            if not (good(m.get(f"{a}{k}", float('nan')), r) and good(m.get(f"{an}{k}", float('nan')), not r)):
                bad.append((a, k))
    return bad


def run(tb):
    fn = os.path.join(tempfile.gettempdir(), f"pff_tb_{tb['name']}.cir")
    open(fn, "w").write(deck(tb))
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True, timeout=600).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


if __name__ == "__main__":
    tb = bench(); m = run(tb)
    print(f"== {tb['name']}: {len(m)} values, errors {check(tb, m) or 'none'}")
    print(" ".join(f"{a}={b:.4g}" for a, b in m.items()))
