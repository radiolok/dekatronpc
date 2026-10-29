#!/usr/bin/env python3
"""Testbench definitions shared by the KiCad testbenches (tools/kicad/gen_latch_j2n16.py) and the plain-SPICE
reference runs, for RSLATCH_J2N16, DLATCH2_J2N16, DFF_J2N16 and DFFRN_J2N16X7 / DFFSN_J2N16X7 (sch/logic/RSLATCH_J2N16/README.md).

Each testbench: ideal HV sources (PWL) -> divider -> driver (6N16B triode, Ra 10k; second triode cut off) ->
divider -> DUT input; each DUT output -> one divider -> load tubes (6N16B, both grids on the net).
Node names are the KiCad ones (/S, /Q, /DUT/FQ ...), so the .meas lines are the same in both runs.

usage: latch_tb.py [rslatch|dlatch2|dff|dffrn|dffsn ...]     runs the plain-SPICE reference and prints the .meas values
"""
import os, re, subprocess, sys, tempfile
import latch_sweep as L
import dff_sweep as D

P = dict(L.BASE, **L.CHOSEN, edge="neg")
C1 = dict(g=P['C1g'], p=P['C1p'], g3=P['C1g3'], f=P['C1f'])


def pwl_pts(times, bits):
    """(t_us, V) points of the inverted-bit HV source (the driver inverts): bit 1 -> 50 V at the source"""
    v = lambda b: 50 if b else 150
    pts = [(0.0, v(bits[0]))]
    for t, b, pb in zip(times[1:], bits[1:], bits[:-1]):
        if b != pb: pts += [(t, v(pb)), (t + 0.02, v(b))]
    return pts


def slots(bits, T):
    return [i * T for i in range(len(bits))], list(bits)


def rslatch_tb():
    seq = L.SEQ
    src = {k: slots([s[i] for s in seq], L.T) for i, k in enumerate("SRE")}
    stop = L.T * len(seq)
    nodes = dict(s="/S", r="/R", e="/E", q="/Q", qn="/QN", lq="/DUT/FQ", lqn="/DUT/FQN", yq="/Q_LV")
    meas = L.meas_lines(seq, nodes, stop)
    return dict(name="RSLATCH_J2N16", src=src, inputs={"S": C1['p'], "R": C1['p'], "E": 2 * C1['g3']},
                outputs={"Q": 6, "QN": 6}, stop=stop, meas=meas,
                note="States (S,R,E) 2 us each: 011 000 100 101 100 010 011 001 101 001 011 000 (latch_sweep.SEQ).")


def dlatch2_tb():
    per = 2.0
    ct, cb, dt, db, samp, ref, stop = D.stimulus("dlatch", per, 0.25, "neg")
    d2 = [1 - b for b in db]
    src = {"E": (ct, cb), "D1": (dt, db), "D2": (dt, d2)}
    meas = [f"meas tran q{k} find v(/Q1) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran n{k} find v(/QN1) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran p{k} find v(/Q2) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran m{k} find v(/QN2) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran {n}min min v({x}) from=0.5u to={stop}u" for n, x in
             (("e", "/E"), ("d1", "/D1"), ("d2", "/D2"), ("r1", "/DUT/R1"), ("y", "/Q1_LV"))]
    meas += [f"meas tran teq trig v(/E) val=-5 rise=1 td={3*per+0.1:.2f}u targ v(/Q1) val=100 rise=1 td={3*per+0.1:.2f}u"]
    return dict(name="DLATCH2_J2N16", src=src, inputs={"E": 4 * C1['g3'], "D1": C1['p'] + C1['g'], "D2": C1['p'] + C1['g']},
                outputs={"Q1": 6, "QN1": 6, "Q2": 2, "QN2": 2}, stop=stop, meas=meas, ref=ref, ref2=[1 - b for b in ref],
                note=f"E: {per} us period, high in the second half; D1 = pattern, D2 = ~D1, both change {per/4} us after E falls.")


def dff_tb():
    per = 1.0
    ct, cb, dt, db, samp, ref, stop = D.stimulus("dff", per, 0.25, "neg")
    src = {"C": (ct, cb), "D": (dt, db)}
    meas = [f"meas tran q{k} find v(/Q) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran n{k} find v(/QN) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran {n}min min v({x}) from=0.5u to={stop}u" for n, x in
             (("c", "/C"), ("d", "/D"), ("es", "/DUT/ES"), ("rm", "/DUT/RM"), ("ss", "/DUT/SS"), ("y", "/Q_LV"))]
    meas += [f"meas tran tcq_r trig v(/C) val=-5 fall=1 td={3*per+0.1:.2f}u targ v(/Q) val=100 rise=1 td={3*per+0.1:.2f}u"]
    return dict(name="DFF_J2N16", src=src, inputs={"C": 2 * C1['g3'] + C1['g'], "D": C1['p'] + C1['g']},
                outputs={"Q": 6, "QN": 6}, stop=stop, meas=meas, ref=ref,
                note=f"C: {per} us period (1 MHz); Q takes D at the falling edge of C; D changes {per/4} us after it.")


RST = (8.2, 11.7)     # the reset line at GND from 8.2 to 11.7 us: asserted while C is low, released 0.3 us before C falls


def dffr_tb(mode):
    """DFFRN_J2N16X7 (mode 'clr') / DFFSN_J2N16X7 ('pre'): the DFF bench, with the reset line asserted once"""
    per = 1.0
    ct, cb, dt, db, samp, ref, stop = D.stimulus("dff", per, 0.25, "neg")
    hold = 0 if mode == "clr" else 1
    ref = [hold if (k + 1) * per + per > RST[0] + 0.1 and (k + 1) * per < RST[1] else r for k, r in enumerate(ref)]
    pin = "RN" if mode == "clr" else "SN"
    idle = -20
    line = [(0.0, idle), (RST[0], idle), (RST[0] + 0.02, 0), (RST[1], 0), (RST[1] + 0.02, idle)]
    meas = [f"meas tran q{k} find v(/Q) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran n{k} find v(/QN) at={t:.4f}u" for k, t in enumerate(samp)]
    meas += [f"meas tran {n}min min v({x}) from=0.5u to={stop}u" for n, x in (("c", "/C"), ("d", "/D"), ("y", "/Q_LV"))]
    lv, d = (92, "fall") if mode == "clr" else (118, "rise")
    meas += [f"meas tran t_rst trig v(/{pin}) val={idle / 2} rise=1 targ v(/Q) val={lv} {d}=1 td={RST[0] - 0.1:.2f}u",
             f"meas tran qhold_{'max' if mode == 'clr' else 'min'} {'max' if mode == 'clr' else 'min'} v(/Q) "
             f"from={RST[0] + 0.8:.2f}u to={RST[1]:.2f}u",
             f"meas tran irst min i(VS{pin}) from={RST[0] + 0.1:.2f}u to={RST[1]:.2f}u"]
    name = "DFFRN_J2N16X7" if mode == "clr" else "DFFSN_J2N16X7"
    return dict(name=name, src={"C": (ct, cb), "D": (dt, db)}, lines={pin: line}, mode=mode,
                inputs={"C": 2 * C1['g3'] + C1['g'], "D": C1['p'] + C1['g']},
                outputs={"Q": 6, "QN": 6}, stop=stop, meas=meas, ref=ref,
                note=f"As DFF_J2N16_tb; {pin} (the reset line, idle {idle} V) at GND from {RST[0]} to {RST[1]} us.")


TBS = dict(rslatch=rslatch_tb, dlatch2=dlatch2_tb, dff=dff_tb, dffrn=lambda: dffr_tb("clr"), dffsn=lambda: dffr_tb("pre"))


# ------------------------------------------------------------- plain SPICE, same node names as KiCad
def _rename(net, m):
    out = []
    for line in net.splitlines():
        w = line.split()
        out.append(" ".join(m.get(x, x) for x in w))
    return "\n".join(out) + "\n"


def deck(tb):
    p = P
    s = f"* {tb['name']} testbench, plain SPICE\n.include {L.LIBS}/6Zh2B.sub\n.include {L.LIBS}/6N16B.sub\n"
    s += "VCC vcc 0 150\nVNB nb 0 -50\n"
    for k, (times, bits) in tb['src'].items():
        pts = " ".join(f"{t:.4f}u {v}" for t, v in pwl_pts(times, bits))
        s += f"VS{k} hs{k} 0 PWL({pts})\n" + L.div(f"s{k}", f"hs{k}", f"is{k}", p, p['C1g'])
        s += f"XD{k} pd{k} is{k} 0 pdx{k} nb 0 6N16B\nRD{k} vcc pd{k} 10k\nRDX{k} vcc pdx{k} 10k\n"
        s += L.div(f"d{k}", f"pd{k}", f"/{k}", p, tb['inputs'][k])
    n = tb['name']
    if n == "RSLATCH_J2N16":
        s += _rename(L.rslatch("x", "/S", "/R", "/E", "/Q", "/QN", p)[0], {"fqx": "/DUT/FQ", "fqnx": "/DUT/FQN"})
    elif n == "DLATCH2_J2N16":
        s += D.inv("x", "/D1", "/DUT/DN1", p, other=("/D2", "/DUT/DN2"))
        for i in (1, 2):
            s += L.div(f"x{i}", f"/DUT/DN{i}", f"/DUT/R{i}", p, p['C1p'])
            s += L.rslatch(f"x{i}", f"/D{i}", f"/DUT/R{i}", "/E", f"/Q{i}", f"/QN{i}", p)[0]
    elif n == "DFF_J2N16":
        s += _rename(D.dff("x", "/D", "/C", "/Q", "/QN", p),
                     {"rmx": "/DUT/RM", "ecx": "/DUT/ES", "ssx": "/DUT/SS", "rsx": "/DUT/RS"})
    else:
        import dffr_sweep as R
        R.OPT['comp'] = 2.7
        s = s.replace(".include", f".include {os.path.join(L.LIBS, '6Kh7B.sub')}\n.include", 1)
        pin = list(tb['lines'])[0]
        pts = " ".join(f"{t:.4f}u {v}" for t, v in tb['lines'][pin])
        s += f"VS{pin} /{pin} 0 PWL({pts})\n"
        s += R.dffr("x", "/D", "/C", "/Q", "/QN", p, tb['mode'], f"/{pin}")
    for o, ng in tb['outputs'].items():
        s += L.div(f"y{o}", f"/{o}", f"/{o}_LV", p, p['C1g'] * ng) + L.loads(f"/{o}_LV", p, ng, o)
    s += f".tran 5n {tb['stop']:.3f}u\n.control\nrun\n" + "\n".join(tb['meas']) + "\n.endc\n.end\n"
    return s


def run(tb):
    fn = os.path.join(tempfile.gettempdir(), f"latch_tb_{tb['name']}.cir")
    open(fn, "w").write(deck(tb))
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


if __name__ == "__main__":
    for k in sys.argv[1:] or list(TBS):
        tb = TBS[k](); m = run(tb)
        print(f"== {tb['name']}: {len(m)} values")
        print(" ".join(f"{a}={b:.4g}" for a, b in m.items()))
