#!/usr/bin/env python3
"""Anode-gated cathode follower (doc/anode_gated_follower.md): static check of Y = A · B.
One 6N16B triode: plate = input A (HV net), grid = input B (LV, its own 470k / 200k divider from the HV net),
cathode -> Rs 2.2k -> Y -> Rk 12k -> -50 V (BUF_N16 values). Y drives 10 load grids (5 NOT-type tubes, Ra 10k).
  1) A from an ideal source: the truth table at HV levels and below them
  2) A swept 150 .. 0 V with B = 1: where the load plate crosses 92 / 118 V
  3) A from a real gate plate (Ra 10k to +150, driver grid -20 V / clamped +0.3 V)
  4) two gated followers on one cathode load (AO22): A1=1 B1=0, A2=HV '0' B2=1
usage: agf_static.py"""
import subprocess, re, os, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NGRUN = os.path.join(HERE, "ngrun.py")
MODEL = os.path.join(HERE, "..", "..", "sch", "libs", "6N16B.sub")
LOADS = "".join(f"XL{i} pl{i} y 0 pm{i} y 0 6N16B\nRL{i} vcc pl{i} 10k\nRM{i} vcc pm{i} 10k\n" for i in range(5))


def run(body, pr):
    d = (f"* agf\n.include {MODEL}\nVCC vcc 0 150\nVNB nb 0 -50\n{body}\n"
         f".control\nop\nprint {pr}\n.endc\n.end\n")
    fn = os.path.join(tempfile.gettempdir(), f"agf_{os.getpid()}.cir")
    open(fn, "w").write(d)
    o = subprocess.run(["python3", NGRUN, fn], capture_output=True, text=True, timeout=60).stdout
    return {k: float(x) for k, x in re.findall(r"^(\S+) = ([-\d.e+]+)", o, re.M)}


def cell(anode):
    return (f"R1 hvb g 470k\nR2 g nb 200k\nXX {anode} g k nc1 nc2 nc3 6N16B\n"
            "Rn1 nc1 0 1G\nRn2 nc2 0 1G\nRn3 nc3 0 1G\nRS k y 2.2k\nRK y nb 12k\n" + LOADS)


def driver(vg):
    return f"VD gd 0 {vg}\nXD a gd 0 n4 n5 n6 6N16B\nRn4 n4 0 1G\nRn5 n5 0 1G\nRn6 n6 0 1G\nRA vcc a 10k\n"


if __name__ == "__main__":
    print("1) ideal A source; B on the HV net: 147 V = '1', 55 V = '0'")
    for va in (150, 50, 0, -20):
        for vb in (147, 55):
            v = run(f"VA a 0 {va}\nVB hvb 0 {vb}\n" + cell("a"), "v(y) v(g) v(pl0) i(VA)")
            print(f"  A={va:4} B={vb:3}: Y={v['v(y)']:7.2f} gridB={v['v(g)']:7.2f} "
                  f"load plate={v['v(pl0)']:6.1f} Ia={-v['i(va)'] * 1e3:5.2f} mA")
    print("2) A swept, B = 1")
    for va in (150, 100, 60, 50, 40, 35, 30, 20, 10, 0):
        v = run(f"VA a 0 {va}\nVB hvb 0 147\n" + cell("a"), "v(y) v(g) v(pl0) i(VA)")
        print(f"  A={va:4}: Y={v['v(y)']:7.2f} gridB={v['v(g)']:7.2f} load plate={v['v(pl0)']:6.1f} "
              f"Ia={-v['i(va)'] * 1e3:5.2f} mA")
    print("3) A from a gate plate (Ra 10k), B = 1")
    for vg in (-20, 0.3):
        v = run(driver(vg) + "VB hvb 0 147\n" + cell("a"), "v(y) v(a) v(pl0)")
        print(f"  driver grid {vg:5}: A={v['v(a)']:6.1f} Y={v['v(y)']:7.2f} load plate={v['v(pl0)']:6.1f}")
    print("4) AO22 on one cathode load: A1=150 B1=0, A2=50 B2=1 (expected Y = 0)")
    s = ("VA1 a1 0 150\nVA2 a2 0 50\nVB1 hb1 0 55\nVB2 hb2 0 147\nR1 hb1 g1 470k\nR2 g1 nb 200k\n"
         "R3 hb2 g2 470k\nR4 g2 nb 200k\nXX a1 g1 k a2 g2 k 6N16B\nRS k y 2.2k\nRK y nb 12k\n" + LOADS)
    v = run(s, "v(y) v(pl0)")
    print(f"  Y={v['v(y)']:.2f} load plate={v['v(pl0)']:.1f}")
