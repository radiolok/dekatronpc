#!/usr/bin/env python3
"""BUF_N16 / OR2_N16 static checks (sch/logic/BUF_N16/README.md): DC transfer and operating points.
One cathode follower (BUF half; OR2 is the same stage with the second triode cut off or in parallel):
plate -> +150 V, cathode -> Rs -> Y -> Rk -> -50 V. The input is the HV net of a driver plate through the
470k / 200k divider (DC: C1 and Cs do not matter). Y drives N grids of NOT_N16 load tubes.
  .dc  : the driver plate swept 30..160 V -> Y, the load plate, Ik, Pa; VIL / VIH of the follower on the HV net
  .op  : levels, Ik, Pa and load grid current for HV inputs 147 V (driver "1") and 55 V (worst driver "0"),
         fanout 0 / 2 / 10, for BUF, OR2 one input high and OR2 both inputs high, model spread
usage: cf_static.py [csv_out]   (csv: hv, then Y and the load plate for N = 2 and 10, for the plots)"""
import subprocess, re, sys, os, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cf_sweep import NGRUN, MODEL, DEFAULT

P = dict(DEFAULT)


def deck(body, ctl, M=""):
    return f"""* CF static
.include {MODEL}
VCC vcc 0 150
VNB nb 0 -50
{body}
.control
{ctl}
.endc
.end
"""


def cell(n, both, M, hv_a="hva", hv_b="hvb"):
    """follower(s) + loads; both=True ties both triodes to one Y (OR2), grid B from its own divider"""
    s = (f"R1a {hv_a} ga {P['R1']}\nR2a ga nb {P['R2']}\nR1b {hv_b} gb {P['R1']}\nR2b gb nb {P['R2']}\n"
         f"XX vcc ga ka vcc gb kb 6N16B {M}\nVK ka k 0\n")
    s += "VKB kb k 0\n" if both else "RKB kb nb 1G\n"
    s += f"RS k y {P['Rs']}\nRK y nb {P['Rk']}\n"
    for i in range(n // 2):
        s += (f"XL{i} pl{i} y 0 pm{i} y 0 6N16B {M}\nRL{i} vcc pl{i} 10k\nRM{i} vcc pm{i} 10k\n")
    if n == 0:
        s += "RL0 vcc pl0 1G\n"
    return s


def run(text):
    fn = os.path.join(tempfile.gettempdir(), f"cf_static_{os.getpid()}.cir")
    open(fn, "w").write(text)
    return subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True).stdout


def op(n, va, vb, both, M=""):
    body = f"VA hva 0 {va}\nVB hvb 0 {vb}\n" + cell(n, both, M)
    o = run(deck(body, "op\nprint v(y) v(k) v(ga) v(gb) v(pl0) i(VK)" + (" i(VKB)" if both else ""), M))
    v = {k: float(x) for k, x in re.findall(r"^(\S+) = ([-\d.e+]+)", o, re.M)}
    ik = v["i(vk)"] + v.get("i(vkb)", 0)
    ig_load = (ik - (v["v(y)"] + 50) / float(P["Rk"].replace("k", "e3"))) / max(n, 1)
    return dict(y=v["v(y)"], k=v["v(k)"], g=v["v(ga)"], pl=v["v(pl0)"], ik=ik, ika=v["i(vk)"],
                pa=(150 - v["v(k)"]) * max(v["i(vk)"], v.get("i(vkb)", 0)), igl=ig_load)


def dc(n, M=""):
    body = "VA hva 0 100\nVB hvb 0 30\n" + cell(n, False, M)
    o = run(deck(body, "dc VA 30 160 0.5\nwrdata " + os.path.join(tempfile.gettempdir(), f"cf_dc_{os.getpid()}.txt")
                 + " v(y) v(pl0) i(VK)", M))
    rows = []
    for line in open(os.path.join(tempfile.gettempdir(), f"cf_dc_{os.getpid()}.txt")):
        f = line.split()
        if len(f) >= 6:
            rows.append((float(f[0]), float(f[1]), float(f[3]), float(f[5])))
    return rows   # hv, y, load plate, ik


def thresholds(rows):
    """on the HV input net: VIL = load plate leaves 150 V (falls below 140 V), switching = load plate 100 V,
    VIH = load plate below 92 V (the next stage's HV '0' threshold)"""
    f = lambda c: next((r[0] for r in rows if r[2] < c), float('nan'))
    return f(140), f(100), f(92)


if __name__ == "__main__":
    print("operating points (HV in 147 / 55 V; OR2: one input high, other at 55 V; both = both high)")
    for M in ("", "MU=20.8", "MU=31.2", "KG1=418", "KG1=697"):
        for n in (0, 2, 10):
            for name, va, vb, both in (("BUF 1", 147, 55, False), ("BUF 0", 55, 55, False),
                                       ("OR2 10", 147, 55, True), ("OR2 11", 147, 147, True), ("OR2 00", 55, 55, True),
                                       ("OR2 00 NOR", 39, 39, True)):
                r = op(n, va, vb, both, M)
                print(f"{M or 'nominal':9s} N={n:2d} {name:10s} Y {r['y']:6.2f} V  grid {r['g']:6.2f}  cathode {r['k']:6.2f}"
                      f"  load plate {r['pl']:6.1f}  Ik {r['ik']*1e3:5.2f} mA  Pa {r['pa']:4.2f} W  Ig/load {r['igl']*1e3:5.2f} mA")
    print("\nDC transfer, input on the HV net (driver plate)")
    out = {}
    for n in (2, 10):
        rows = dc(n)
        out[n] = rows
        vil, vsw, vih = thresholds(rows)
        print(f"N={n:2d}: load plate < 140 V at HV {vil:5.1f} V, = 100 V at {vsw:5.1f} V, < 92 V at {vih:5.1f} V")
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as fo:
            fo.write("hv,y2,pl2,y10,pl10,ik10\n")
            for a, b in zip(out[2], out[10]):
                fo.write(f"{a[0]},{a[1]},{a[2]},{b[1]},{b[2]},{b[3]}\n")
