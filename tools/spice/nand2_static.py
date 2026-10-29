#!/usr/bin/env python3
"""NAND2_J2 static checks (sch/logic/NAND2_J2/README.md): operating points per input state and transfer curves.

usage: nand2_static.py            prints levels, currents and dissipation per state (MU2 nominal and +-20 %),
                                  and the transfer thresholds of each input with the other input high.
Inputs come from HV sources (50/150 V) through the HV->LV divider, the output drives one divider and N grids
(N/2 load gates with g1 and g3 tied); the cell is the chosen one (Ra, Rg2, Cb).
"""
import os, re, subprocess, sys, tempfile
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6Zh2B.sub")
CELL = dict(Ra="15k", Rg2="15k")
N = 10


def deck(va, vb, m="", analysis=".op", out=""):
    s = f"""* NAND2_J2 static
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
VA ha 0 {va}
VB hb 0 {vb}
R1A ha a 470k
R2A a nb 200k
R1B hb b 470k
R2B b nb 200k
XD pd b sd 0 a 6Zh2B {m}
RA vcc pdr {CELL['Ra']}
VIA pdr pd 0
RS vcc sdr {CELL['Rg2']}
VIS sdr sd 0
R1Y pd yl 470k
R2Y yl nb 200k
"""
    for i in range(N // 2):
        s += f"XL{i} pl{i} yl sl{i} 0 yl 6Zh2B {m}\nRAL{i} vcc pl{i} {CELL['Ra']}\nRSL{i} vcc sl{i} {CELL['Rg2']}\n"
    s += f".control\n{analysis}\n{out}\n.endc\n.end\n"
    return s


def ngrun(text):
    fn = os.path.join(tempfile.mkdtemp(), "d.cir")
    open(fn, "w").write(text)
    return subprocess.run([sys.executable, NGRUN, fn], capture_output=True, text=True).stdout


def op(va, vb, m=""):
    o = ngrun(deck(va, vb, m, "op", "print v(pd) v(sd) v(a) v(b) v(yl) i(VIA) i(VIS)"))
    v = dict(re.findall(r"^([\w()]+) = ([-\d.e+]+)", o, re.M))
    f = {k: float(x) for k, x in v.items()}
    ua, us, ira, ig2 = f["v(pd)"], f["v(sd)"], f["i(via)"], f["i(vis)"]
    ia = ira - (ua - f["v(yl)"]) / 470e3                # Ra current minus the output divider
    return dict(Y=ua, Ug2=us, A=f["v(a)"], B=f["v(b)"], YL=f["v(yl)"], Ia=ia * 1e3, Ig2=ig2 * 1e3,
                Ik=(ia + ig2) * 1e3, Pa=ua * ia, Pg2=us * ig2)


def transfer(which, m=""):
    """sweep the HV source of one input, the other input high; returns hv, lv input, Y"""
    tmp = tempfile.mkdtemp(); data = os.path.join(tmp, "dc.txt")
    va, vb = ("0", "150") if which == "A" else ("150", "0")
    src = "VA" if which == "A" else "VB"
    node = "a" if which == "A" else "b"
    ngrun(deck(va, vb, m, f"dc {src} 40 150 0.25", f"wrdata {data} v({node}) v(pd)"))
    d = np.loadtxt(data)
    return d[:, 0], d[:, 1], d[:, 3]


def thresholds(hv, lv, y):
    dy = np.gradient(y, lv)
    i_vil = np.where(dy <= -1)[0][0]                    # first point where slope reaches -1 (from the low side)
    i_vih = np.where(dy <= -1)[0][-1]                   # last point with slope -1 (from the high side)
    i_sw = np.where(y <= 100)[0][0]                     # output crosses the HV middle
    return dict(VIL_lv=lv[i_vil], VIL_hv=hv[i_vil], SW_lv=lv[i_sw], SW_hv=hv[i_sw], VIH_lv=lv[i_vih], VIH_hv=hv[i_vih])


if __name__ == "__main__":
    for m, nm in (("", "MU2 nominal"), ("MU2=16.03", "MU2 -20 %"), ("MU2=24.04", "MU2 +20 %")):
        print(nm)
        for va, vb, st in ((50, 50, "00"), (150, 50, "10"), (50, 150, "01"), (150, 150, "11")):
            r = op(va, vb, m)
            print(f"  AB={st}: Y {r['Y']:6.1f} V  Ug2 {r['Ug2']:5.1f} V  A {r['A']:6.2f} B {r['B']:6.2f} YL {r['YL']:6.2f} V"
                  f"  Ia {r['Ia']:5.2f} Ig2 {r['Ig2']:5.2f} Ik {r['Ik']:5.2f} mA  Pa {r['Pa']:.2f} Pg2 {r['Pg2']:.2f} W")
    for which in ("A", "B"):
        t = thresholds(*transfer(which))
        print(f"transfer {which}: VIL {t['VIL_lv']:.1f} V LV ({t['VIL_hv']:.0f} V HV), switch {t['SW_lv']:.1f} V LV ({t['SW_hv']:.0f} V HV), VIH {t['VIH_lv']:.1f} V LV ({t['VIH_hv']:.0f} V HV)")
