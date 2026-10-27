#!/usr/bin/env python3
"""RSLATCH_J2N16 currents and dissipation per state (doc/latch_j2n16.md), from the sweep deck at fanout 10.

usage: latch_static.py [M="6Zh2B params"] ...   prints, at the end of every state of latch_sweep.SEQ, the plate,
screen and cathode current and dissipation of both pentodes and both triodes, nominal model and MU2 +-20 %.
"""
import os, re, subprocess, sys, tempfile
import latch_sweep as L
N = 10


def meas(seq):
    out = []
    for i in range(len(seq)):
        t = f"at={i*L.T+L.T-0.05:.2f}u"
        for k in ("s", "r"):
            out += [f"meas tran ia{k}{i} find i(VPx{k}) {t}", f"meas tran va{k}{i} find v(ppx{k}) {t}",
                    f"meas tran vs{k}{i} find v(sx{k}) {t}"]
        for k in ("a", "b"):
            out += [f"meas tran it{k}{i} find i(VTx{k}) {t}", f"meas tran vt{k}{i} find v(ptx{k}) {t}"]
    return "\n".join(out) + "\n"


def run(p):
    fn = os.path.join(tempfile.gettempdir(), f"latch_static_{os.getpid()}.cir")
    open(fn, "w").write(L.deck(p, N, extra=meas(L.SEQ)))
    o = subprocess.run(["python3", L.NGRUN, fn], capture_output=True, text=True).stdout
    return {k: float(v) for k, v in re.findall(r"^(\w+)\s+=\s+([-\d.e+]+)", o, re.M)}


def table(name, p):
    m = run(p); rg2 = float(p['Rg2'].replace('k', 'e3'))
    print(f"\n{name}: state S R E Q | pentode S: Ua Ia Ug2 Ig2 Ik Pa Pg2 | pentode R: same | triodes A/B: Ua Ia Pa")
    worst = dict(ik=0, pa=0, pg2=0, pt=0, it=0)
    q = L.model_q(L.SEQ)
    for i, st in enumerate(L.SEQ):
        row = f"{i:2d} {st[0]} {st[1]} {st[2]} {q[i]} |"
        for k in ("s", "r"):
            ia, va, vs = m[f"ia{k}{i}"] * 1e3, m[f"va{k}{i}"], m[f"vs{k}{i}"]
            ig2 = (150 - vs) / rg2 * 1e3
            ik, pa, pg2 = ia + ig2, ia * va / 1e3, ig2 * vs / 1e3
            worst['ik'] = max(worst['ik'], ik); worst['pa'] = max(worst['pa'], pa); worst['pg2'] = max(worst['pg2'], pg2)
            row += f" {va:5.1f} {ia:4.1f} {vs:5.1f} {ig2:4.1f} {ik:4.1f} {pa:4.2f} {pg2:4.2f} |"
        for k in ("a", "b"):
            it, vt = m[f"it{k}{i}"] * 1e3, m[f"vt{k}{i}"]
            worst['pt'] = max(worst['pt'], it * vt / 1e3); worst['it'] = max(worst['it'], it)
            row += f" {vt:5.1f} {it:4.1f} {it*vt/1e3:4.2f}"
        print(row)
    print(f"worst: pentode Ik {worst['ik']:.1f} mA, Pa {worst['pa']:.2f} W, Pg2 {worst['pg2']:.2f} W;"
          f" triode Ik {worst['it']:.1f} mA, Pa {worst['pt']:.2f} W")


if __name__ == "__main__":
    P = dict(L.BASE, **L.CHOSEN)
    table("nominal", P)
    for mu2 in (16.03, 24.04):
        table(f"MU2 = {mu2}", dict(P, M=f"MU2={mu2}"))
