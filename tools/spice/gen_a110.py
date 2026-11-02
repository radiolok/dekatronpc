#!/usr/bin/env python3
"""Generate sch/libs/A110.sub: behavioural ngspice model of the A110 dekatron (doc/dekatron_physics.md).

The tube is a ring of 30 glow gaps between the anode and the electrodes:
  i % 3 == 0 : main cathode K(i/3)           (pins K0..K9, each its own lead)
  i % 3 == 1 : first guide  (guide A, PK1)   (all ten tied to pin G1)
  i % 3 == 2 : second guide (guide B, PK2)   (all ten tied to pin G2)
the same ring order as rtl/DekatronPC/Dekatron/DekatronTubeV2.sv.

Each gap i has an ionization state x_i in 0..1 (node x<i>, 1 F capacitor, volts = fraction):
  ignition voltage  Vz_i = min( VZ0 + dz_i - (VZ0 + dz_i - VB) * x_i,          own ionization
                                VB + UT1 + (VZ0 - VB - UT1) * L(p_i),           neighbour at +-1
                                VB + UT2 + (VZ0 - VB - UT2) * L(q_i) )          neighbour at +-2
      L(p) = min(1, ln(max(p, PMIN)) / ln(PMIN)): the ignition voltage falls with the logarithm of the
      priming (Yablonsky 1967 p.33-35, formula (8)), so a weak neighbouring glow already primes well
      p_i = max(x_{i-1}, x_{i+1}),  q_i = max(x_{i-2}, x_{i+2})
      (Lipkin 1967 p.15, Yablonsky 2-2: transfer voltage Un1 to the adjacent electrode is a few volts,
       Un2 to the electrode one further is much higher; ignition under an auxiliary discharge)
  gap fires         f_i  = (1 + tanh((v_i - Vz_i) / VS)) / 2,   v_i = V(A) - V(electrode)
  ionization target y_i  = max(f_i, min(1, I_i / IN) * x_i / (x_i + XS))
      a struck gap is kept up by its own current; a gap below XS is not (nucleation threshold): below
      its ignition voltage a gap carries no self-sustained discharge (Townsend), so a gap with
      VB + VEX < v < Vz must not grow from numerical noise. Without the factor an unlit cathode 20 V
      below the lit one took the discharge over in ~20 us (sch/logic/DEKATRON_A110/README.md).
  formation / deionization
      dx_i/dt = max(0, y_i - x_i) (1 + max(0, v_i - Vz_i)/UF) / (TF + TF0 (1 - s_i))  -  max(0, x_i - y_i) / TD
      s_i = max(x_i, p_i): a primed gap forms in TF, an unprimed one (power-up, write, reset) in TF+TF0
      (Yablonsky 1-2: statistical lag vanishes next to a burning gap; formation time falls with overvoltage)
  current           I_i  = x_i * max(0, v_i - VB - VEX (1 - x_i)) / RD
      a half-formed discharge burns VEX higher, so of two lit gaps the more formed one takes the
      current and the other goes out (one discharge at a time).
  probe current     a glow on a main cathode sends part of its current to the two adjacent guides
      (Yablonsky 3-1, eq. 3-4, fig. 3-3): I_pk = k I_k, k = KP0 exp(-Ueff / KPU), Ueff = guide - cathode
      (>= 0); the gap current I_i splits as I_i / (1 + k) to the cathode and I_i k / (1 + k) / 2 to each
      neighbouring guide ring. KP0, KPU fitted to the A101 curve of fig. 3-3 (0.20 at 5 V, 0.13 at 20 V,
      0.065 at 47 V); no data for the A110.

All numbers are estimates until the tube is measured (OPEN-013, OPEN-014); only VB (175-205 V) and the
anode current (0.7-0.9 mA) are on the A110 sheet (doc/a110_datasheet.md).

usage: gen_a110.py [-o sch/libs/A110.sub] [--seed N] [--mismatch V]
"""
import argparse
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "..", "sch", "libs", "A110.sub")

PARAMS = [
    ("VB", "190", "burning voltage of a formed glow, V (sheet: 175-205)"),
    ("VZ0", "330", "static ignition voltage of an unprimed gap, V (estimate: < 350 V supply, VB + reset 150 V)"),
    ("UT1", "5", "transfer voltage to an electrode next to the glow, V (estimate)"),
    ("UT2", "60", "transfer voltage to an electrode one further, V (estimate)"),
    ("PMIN", "1e-3", "priming level that no longer lowers the ignition voltage (estimate)"),
    ("VEX", "20", "extra burning voltage of an unformed discharge, V (estimate)"),
    ("RD", "2k", "dynamic resistance of the glow (estimate)"),
    ("TF", "50n", "formation time next to a glow (estimate, 1 MHz class)"),
    ("TF0", "1u", "extra formation time without priming: power-up, write, reset (estimate)"),
    ("TD", "1u", "deionization time constant (estimate; 300 ns loses the A->B hand-over, doc/dekatron_physics.md)"),
    ("UF", "20", "overvoltage that halves the formation time, V (estimate)"),
    ("VS", "0.3", "softness of the ignition threshold, V (numerical)"),
    ("IN", "0.6m", "current that keeps a gap fully ionized; above half the working current, so a shared glow is unstable (estimate)"),
    ("XS", "0.02", "nucleation threshold: ionization below it is not kept up by the gap current (estimate)"),
    ("MIS", "1", "scale of the per-gap ignition mismatch dz_i"),
    ("KP0", "0.22", "probe current ratio to the guides at Ueff = 0 (Yablonsky fig. 3-3, A101)"),
    ("KPU", "38", "Ueff that lowers the probe ratio e times, V (Yablonsky fig. 3-3, A101)"),
    ("CAK", "0.5p", "anode - one main cathode"),
    ("CAG", "2.5p", "anode - one guide ring (ten guides)"),
]


def name(i):
    i %= 30
    return f"K{i // 3}" if i % 3 == 0 else ("G1" if i % 3 == 1 else "G2")


def x(i):
    return f"v(x{i % 30})"


def build(seed, mismatch):
    rnd = random.Random(seed)
    dz = [round(rnd.uniform(-mismatch, mismatch), 2) for _ in range(30)]
    pins = " ".join(["A"] + [f"K{k}" for k in range(10)] + ["G1", "G2"])
    L = ["* A110 (А-110) dekatron, behavioural ngspice model. Generated by tools/spice/gen_a110.py,",
         f"* seed {seed}, mismatch +-{mismatch} V. Do not edit: change the generator. doc/dekatron_physics.md",
         "* pins: A anode, K0..K9 main cathodes, G1 first guides (PK1, pin 9), G2 second guides (PK2, pin 5)",
         "* pin numbers of the tube (sheet): A 13, K0 12, K1 11, K2 10, K3 8, K4 7, K5 6, K6 4, K7 3, K8 2, K9 1",
         f".subckt A110 {pins}"]
    L.append(".param " + " ".join(f"{n}={v}" for n, v, _ in PARAMS))
    for n, v, c in PARAMS:
        L.append(f"* {n:4} = {v:5} : {c}")
    for i in range(30):
        e = name(i)
        v = f"(v(A)-v({e}))"
        p = f"max({x(i - 1)},{x(i + 1)})"
        q = f"max({x(i - 2)},{x(i + 2)})"
        vz0 = f"(VZ0+MIS*({dz[i]}))"
        lp = f"min(1,ln(max({p},PMIN))/ln(PMIN))"
        lq = f"min(1,ln(max({q},PMIN))/ln(PMIN))"
        vz = (f"min({vz0}-({vz0}-VB)*{x(i)},"
              f"min(VB+UT1+(VZ0-VB-UT1)*{lp},VB+UT2+(VZ0-VB-UT2)*{lq}))")
        L.append(f"Bz{i} z{i} 0 V = {vz}")
        cur = f"{x(i)}*max(0,{v}-VB-VEX*(1-{x(i)}))/RD"
        L.append(f"Bf{i} f{i} 0 V = 0.5*(1+tanh(({v}-v(z{i}))/VS))")
        L.append(f"By{i} y{i} 0 V = max(v(f{i}),min(1,{cur}/IN)*{x(i)}/({x(i)}+XS))")
        L.append(f"Bx{i} 0 x{i} I = max(0,v(y{i})-{x(i)})*(1+max(0,{v}-v(z{i}))/UF)"
                 f"/(TF+TF0*(1-max({x(i)},{p})))-max(0,{x(i)}-v(y{i}))/TD")
        L.append(f"Cx{i} x{i} 0 1")
        L.append(f"Rx{i} x{i} 0 1G")
        if i % 3 == 0:
            # main cathode: part of the current goes to the adjacent guides (probe current)
            kp = (f"(KP0*exp(-max(0,min(v({name(i + 1)})-v({e}),v({name(i - 1)})-v({e})))/KPU))")
            L.append(f"Bk{i} kp{i} 0 V = {kp}")
            L.append(f"Bi{i} A {e} I = {cur}/(1+v(kp{i}))")
            L.append(f"Bp{i}a A {name(i + 1)} I = {cur}*v(kp{i})/(1+v(kp{i}))/2")
            L.append(f"Bp{i}b A {name(i - 1)} I = {cur}*v(kp{i})/(1+v(kp{i}))/2")
        else:
            L.append(f"Bi{i} A {e} I = {cur}")
    for k in range(10):
        L.append(f"Ck{k} A K{k} {{CAK}}")
    L.append("Cg1 A G1 {CAG}")
    L.append("Cg2 A G2 {CAG}")
    L.append(".ends A110")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", default=DEFAULT_OUT)
    ap.add_argument("--seed", type=int, default=110)
    ap.add_argument("--mismatch", type=float, default=3.0, help="+- V of per-gap ignition voltage spread")
    a = ap.parse_args()
    with open(a.o, "w") as f:
        f.write(build(a.seed, a.mismatch))
    print(a.o)
