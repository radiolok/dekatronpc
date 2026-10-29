#!/usr/bin/env python3
"""A1OOI_N16J2 / A2OOI_J2 static checks: operating point of every input state, nominal model and the
6Zh2B screen spread MU2 +-20 %. Inputs come from HV levels (NOT driver: "1" 146.9 V, "0" 55 V) through
the 470k / 200k divider to -50 V, as on a real net.

usage: aoi_static.py [a1|a22|n4 ...]
"""
import itertools, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aoi_sweep as A   # noqa: E402

HV = {0: 55.0, 1: 146.9}
PENT = {"A1OOI_N16J2": ["1"], "A2OOI_J2": ["1", "2"], "NOR4_N16": []}
TRI = {"A1OOI_N16J2": ["1"], "A2OOI_J2": [], "NOR4_N16": ["1", "2", "3", "4"]}
SPREAD = [("nominal", {}), ("MU2 -20 %", dict(M="MU2=16.03")), ("MU2 +20 %", dict(M="MU2=24.04")),
          ("MU -20 %", dict(MN="MU=20.77")), ("KG1 -25 %", dict(MN="KG1=418.2"))]


def deck(c, state, p):
    s = f"* {c['name']} static\n.include {A.LIBS}/6Zh2B.sub\n.include {A.LIBS}/6N16B.sub\n"
    s += "VCC vcc 0 150\nVNB nb 0 -50\nVNB20 nb20 0 -20\n"
    ins = {}
    for pin, b in zip(c['pins'], state):
        n = pin.lower(); ins[pin] = n
        s += f"VH{n} h{n} 0 {HV[b]}\nR1{n} h{n} {n} 470k\nR2{n} {n} nb 200k\n"
    s += A.cell_net(c, ins, "y", p)
    pent, tri = PENT[c['name']], TRI[c['name']]
    pr = ["v(y)"] + [f"i(VP{t})" for t in pent] + [f"v(s{t})" for t in pent] + [f"i(VT{t})" for t in tri]
    s += ".control\nop\n" + "\n".join(f"print {x}" for x in pr) + "\n.endc\n.end\n"
    return s


def op(c, state, p):
    fn = os.path.join(tempfile.gettempdir(), f"aoi_static_{os.getpid()}.cir")
    open(fn, "w").write(deck(c, state, p))
    o = subprocess.run([sys.executable, A.NGRUN, fn], capture_output=True, text=True).stdout
    return {k.lower(): float(v) for k, v in re.findall(r"^(\S+)\s+=\s+([-\d.e+]+)", o, re.M)}


if __name__ == "__main__":
    keys = [a for a in sys.argv[1:] if a in A.CELLS] or list(A.CELLS)
    for key in keys:
        c = A.CELLS[key]
        pent, tri = PENT[c['name']], TRI[c['name']]
        worst = dict(ik=0, pa=0, pg2=0, ug2=0, tik=0, tpa=0)
        print(f"== {c['name']}")
        for case, ov in SPREAD:
            p = {**A.params(key), **ov}
            for state in itertools.product((0, 1), repeat=len(c['pins'])):
                m = op(c, state, p)
                y = m["v(y)"]
                row = []
                for t in pent:
                    ia = m[f"i(vp{t})"]; us = m[f"v(s{t})"]; ig2 = (150 - us) / 15e3
                    ik, pa, pg2 = ia + ig2, ia * y, ig2 * us
                    worst.update(ik=max(worst['ik'], ik), pa=max(worst['pa'], pa), pg2=max(worst['pg2'], pg2),
                                 ug2=max(worst['ug2'], us if ia > 1e-4 else 0))
                    row.append(f"J{t} Ik {ik*1e3:5.2f} Ia {ia*1e3:5.2f} Ug2 {us:5.1f} Pa {pa:4.2f} Pg2 {pg2:4.2f}")
                for t in tri:
                    it = m[f"i(vt{t})"]; worst.update(tik=max(worst['tik'], it), tpa=max(worst['tpa'], it * y))
                    row.append(f"T{t} Ik {it*1e3:5.2f} Pa {it*y:4.2f}")
                print(f"  {case:10s} {''.join(map(str, state))} Y={c['f'](*state)} {y:6.1f} V | " + " | ".join(row))
        print(f"  worst: 6Zh2B Ik {worst['ik']*1e3:.1f} mA (14), Pa {worst['pa']:.2f} W (0.9), Pg2 {worst['pg2']:.2f} W (0.6),"
              f" Ug2 conducting {worst['ug2']:.0f} V (125); 6N16B Ik {worst['tik']*1e3:.1f} mA (14), Pa {worst['tpa']:.2f} W (0.9)")
