#!/usr/bin/env python3
"""Generate the DFFP2_J2N16 sheets and testbench (sch/logic/DFFP2_J2N16/README.md, doc/tc_n5_pulse_dff.md).

usage: gen_dffp_j2n16.py OUT_DIR
  OUT_DIR/DFFP2_J2N16/DFFP_J2N16.kicad_sch      one pulse-clocked D flip-flop without its D inverter (sub-sheet)
  OUT_DIR/DFFP2_J2N16/DFFP2_J2N16.kicad_sch     the cell: two DFFP_J2N16 + one 6N16B for both D inverters (7 tubes)
  OUT_DIR/DFFP2_J2N16/DFFP2_J2N16_tb.kicad_sch/.kicad_pro   testbench: the two flip-flops as a shift register;
                                                stimulus, part values and .meas from tools/spice/pff_tb.py
Parts are connected by net labels at short pin stubs (as gen_latch_j2n16.py), with the node names of the
plain-SPICE reference. Every run makes new UUIDs: regenerate to start over, edit drawn sheets in KiCad.
"""
import sys, os

OUT = sys.argv[1]
CELL = "DFFP2_J2N16"
os.makedirs(os.path.join(OUT, CELL), exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from kicad_sheet import *  # noqa: E402,F401,F403
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import pff_tb as TB  # noqa: E402

X = TB.CELL
PROJ = "DFFP2_J2N16_tb"
ROOT, DUT, FF1, FF2 = U(), U(), U(), U()

# ---------------------------------------------------------------- DFFP_J2N16: one flip-flop
core = Sheet([(PROJ, f"/{ROOT}/{DUT}/{FF1}", 1), (PROJ, f"/{ROOT}/{DUT}/{FF2}", 2)])
H = {"D": "input", "DN": "input", "C": "input", "Q": "output", "QN": "output", "H1": "passive", "H2": "passive"}
x0, y0 = 45*G, 30*G
# QN half: pentode Л1 (S on g1, G on g3) and triode A (grid FQ) on plate QN; Q half below, mirrored
core.part(J2, (x0, y0), "Л", "6Ж2Б", {"1": "QN", "2": "G", "3": "SG1", "7": "S", **j2_bottom()}, props=SIM[J2], hier=H)
core.part(J2, (x0, y0 + 30*G), "Л", "6Ж2Б", {"1": "Q", "2": "G", "3": "SG2", "7": "R", **j2_bottom()}, props=SIM[J2], hier=H)
tref = core.ref("Л")
core.part(N16, (x0 + 25*G, y0), None, "6Н16Б", {"1": "QN", "7": "FQ", **n16_bottom()}, unit=1, props=SIM[N16], hier=H, refs=tref)
core.part(N16, (x0 + 25*G, y0 + 30*G), None, "6Н16Б", {"5": "Q", "3": "FQN", "2": "GND"}, unit=2, props=SIM[N16], hier=H, refs=tref)
# plates: Ra + La from +150 V; screens Rg2
for yy, node in ((y0 - 8*G, "QN"), (y0 + 22*G, "Q")):
    core.part("Device:R", (x0 + 38*G, yy), "R", X['Ra'], {"1": "+150V", "2": "RA" + node}, hier=H)
    core.part("Device:L", (x0 + 38*G, yy + 10*G), "L", X['La'], {"1": "RA" + node, "2": node}, hier=H)
core.part("Device:R", (x0 + 12*G, y0 - 6*G), "R", X['Rg2'], {"1": "+150V", "2": "SG1"}, hier=H)
core.part("Device:R", (x0 + 12*G, y0 + 24*G), "R", X['Rg2'], {"1": "+150V", "2": "SG2"}, hier=H)
# cross-coupling dividers: Q -> FQ (grid of triode A), QN -> FQN (grid of triode B)
divider(core, x0 + 48*G, y0 + 2*G, "Q", "FQ", X['C1f'], hier=H)
divider(core, x0 + 48*G, y0 + 32*G, "QN", "FQN", X['C1f'], hier=H)
# slow dividers into the pentode g1 (no C1: the data delay), and the clock pulse network on both g3
core.part("Device:R", (12*G, y0 - 4*G), "R", X['R1s'], {"1": "D", "2": "S"}, hier=H)
core.part("Device:R", (20*G, y0 - 4*G), "R", X['R2s'], {"1": "S", "2": "-50V"}, hier=H)
core.part("Device:R", (12*G, y0 + 26*G), "R", X['R1s'], {"1": "DN", "2": "R"}, hier=H)
core.part("Device:R", (20*G, y0 + 26*G), "R", X['R2s'], {"1": "R", "2": "-50V"}, hier=H)
core.part("Device:C", (12*G, y0 + 11*G), "C", X['Cc'], {"1": "C", "2": "G"}, hier=H)
core.part("Device:R", (20*G, y0 + 11*G), "R", X['Rt'], {"1": "G", "2": "GND"}, hier=H)
core.part("Device:R", (28*G, y0 + 11*G), "R", X['Rb'], {"1": "G", "2": "-50V"}, hier=H)
core.text("DFFP_J2N16: pulse-clocked D flip-flop (one half of DFFP2_J2N16; its D inverter is on the parent sheet).\n"
          "Bonch-Bruevich bistable (6N16B, cross-coupled through 470k || 3.9 pF / 200k) steered by two 6Zh2B: QN pentode g1 = S,\n"
          "Q pentode g1 = R, both g3 on G. Plates Ra 10k + La 1 mH (peaking: halves the flip time), screens Rg2 12k.\n"
          "C is the HV clock line: Cc 3.9 pF into G, which rests at -12.4 V (43k to GND, 130k to -50 V). The rising edge lifts G into\n"
          "the g3 grid-current clamp for ~400 ns (above -5 V); the pentode whose g1 is high pulls its plate, the bistable finishes by regeneration.\n"
          "D and DN are HV: 150k / 62k dividers WITHOUT C1 into S and R. The g1 node (~5 pF) delays the data by ~150 ns, so a new D\n"
          "from the next flip-flop cannot reach the gate while the pulse lasts (the race margin). Each D pin loads its net by ~1.2 mA DC.\n"
          "Simulated, fanout 2/6: C -> Q 51-95 / 122-158 ns; setup 341/527 ns, hold -150/-3 ns; lowest grid -40 V (G, falling clock edge).\n"
          "Heater 6.3 V: 2 x 0.2 A + 0.4 A. Page: sch/logic/DFFP2_J2N16/README.md", (10*G, 84*G))
core.dump(os.path.join(OUT, CELL, "DFFP_J2N16.kicad_sch"), "DFFP_J2N16 - pulse-clocked D flip-flop",
          comments=["Q <= D at the rising edge of C; D, DN, C: HV; Q, QN: HV", "2 x 6Zh2B + 6N16B; Ra 10k + La 1 mH, Rg2 12k"], paper="A3")

CORE_PINS = [("D", "input", "L", 1), ("DN", "input", "L", 3), ("C", "input", "L", 5), ("H1", "passive", "L", 8),
             ("H2", "passive", "L", 9), ("Q", "output", "R", 1), ("QN", "output", "R", 3)]
CORE_SIZE = (14*G, 11*G)

# ---------------------------------------------------------------- DFFP2_J2N16: the cell
cell = Sheet([(PROJ, f"/{ROOT}/{DUT}", 9)])
HC = {"D1": "input", "D2": "input", "C1": "input", "C2": "input", "Q1": "output", "QN1": "output", "Q2": "output",
      "QN2": "output", "H1": "passive", "H2": "passive"}
t = cell.ref("Л")
cell.part(N16, (40*G, 25*G), None, "6Н16Б", {"1": "DN1", "7": "DI1", **n16_bottom()}, unit=1, props=SIM[N16], hier=HC, refs=t)
cell.part(N16, (40*G, 50*G), None, "6Н16Б", {"5": "DN2", "3": "DI2", "2": "GND"}, unit=2, props=SIM[N16], hier=HC, refs=t)
cell.part("Device:R", (52*G, 19*G), "R", X['Rinv'], {"1": "+150V", "2": "DN1"}, hier=HC)
cell.part("Device:R", (52*G, 44*G), "R", X['Rinv'], {"1": "+150V", "2": "DN2"}, hier=HC)
divider(cell, 12*G, 27*G, "D1", "DI1", X['C1i'], hier=HC)
divider(cell, 12*G, 52*G, "D2", "DI2", X['C1i'], hier=HC)
for i, (uid, yy) in enumerate(((FF1, 20*G), (FF2, 45*G)), 1):
    nets = {"D": f"D{i}", "DN": f"DN{i}", "C": f"C{i}", "Q": f"Q{i}", "QN": f"QN{i}", "H1": "H1", "H2": "H2"}
    cell.subsheet(f"FF{i}", "DFFP_J2N16.kicad_sch", (80*G, yy), CORE_SIZE, CORE_PINS, nets,
                  [(PROJ, f"/{ROOT}/{DUT}", str(2 + i))], uid, hier=HC)
cell.text("DFFP2_J2N16: two pulse-clocked D flip-flops, Qi takes Di at the RISING edge of Ci. 7 tubes: 2 x DFFP_J2N16 + one 6N16B.\n"
          "The 6N16B inverts D1 and D2 (Ra 10k, grid through 470k || 3.9 pF / 200k); its plates DN1, DN2 go to the slow R dividers.\n"
          "D1, D2: HV pins (the cell has its own dividers; ~1.2 mA DC each, at most two such pins per net). C1, C2: HV clock lines\n"
          "(3.9 pF each, edges up to 300 ns). Q, QN: HV, max fanout 6. Liberty: DFFP_J2N16 = one flip-flop, 3.5 tubes.\n"
          "Page: sch/logic/DFFP2_J2N16/README.md; study: doc/tc_n5_pulse_dff.md", (10*G, 72*G))
cell.dump(os.path.join(OUT, CELL, "DFFP2_J2N16.kicad_sch"), "DFFP2_J2N16 - two pulse-clocked D flip-flops",
          comments=["Qi <= Di at the rising edge of Ci; D, C: HV; Q, QN: HV", "2 x DFFP_J2N16 + 6N16B (D inverters)"], paper="A3")

# ---------------------------------------------------------------- testbench
tb = TB.bench()
sh = Sheet([(PROJ, f"/{ROOT}", "")], uid=ROOT)
x = 10*G
for v, top, bot, y in (("150", "+150V", "GND", 15*G), ("50", "GND", "-50V", 35*G), ("6.3", "+6.3V", "GND", 55*G)):
    props = {"Sim.Device": "V", "Sim.Type": "DC", "Sim.Pins": "1=+ 2=-", "Sim.Params": f"dc={v}"}
    sh.symbol("Simulation_SPICE:VDC", (x, y), 0, sh.ref("V"), v, props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
    for pin, net in (("1", top), ("2", bot)):
        p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, pin)
        e = (p[0], p[1] + d[1] * G)
        sh.wire(p, e); sh.power(net, e, d)
        if net != "GND" or v == "150":
            fp = (e[0] + 3*G, e[1]); sh.wire(e, fp)
            sh.symbol("power:PWR_FLAG", fp, 0, sh.ref("#FLG"), "PWR_FLAG", ref_off=(0, -1.905), val_off=(1.27, -3.81), hide_ref=True, pins=["1"])
# clock line: an ideal HV source on the net (the clock driver of the machine)
pts = " ".join(f"{a:.4f}u {b}" for a, b in TB.clock_pts(*tb['clock']))
sh.part("Simulation_SPICE:VPWL", (30*G, 70*G), "V", "VPWL", {"1": "CK", "2": "GND"},
        props={"Sim.Device": "V", "Sim.Type": "PWL", "Sim.Pins": "1=+ 2=-", "Sim.Params": f'pwl="{pts}"'})
# D1: PWL source -> divider -> 6N16B triode (Ra 10k; second triode cut off); the plate is the HV net D1
pts = " ".join(f"{a:.4f}u {b}" for a, b in TB.d_pts(*tb['d']))
y = 12*G
sh.part("Simulation_SPICE:VPWL", (30*G, y + 4*G), "V", "VPWL", {"1": "STIM_D", "2": "GND"},
        props={"Sim.Device": "V", "Sim.Type": "PWL", "Sim.Pins": "1=+ 2=-", "Sim.Params": f'pwl="{pts}"'})
divider(sh, 38*G, y + 4*G, "STIM_D", "IS_D", "3.9p")
t = sh.ref("Л")
sh.part(N16, (75*G, y + 6*G), None, "6Н16Б", {"1": "D1", "7": "IS_D", **n16_bottom("+6.3V", "GND")}, unit=1, props=SIM[N16], refs=t)
sh.part(N16, (88*G, y + 6*G), None, "6Н16Б", {"5": "PDX_D", "3": "-50V", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
sh.part("Device:R", (65*G, y + 2*G), "R", "10k", {"1": "+150V", "2": "D1"})
sh.part("Device:R", (98*G, y + 2*G), "R", "10k", {"1": "+150V", "2": "PDX_D"})
# DUT: FF1.Q -> FF2.D, both clocks on CK
dut_pins = [("D1", "input", "L", 1), ("D2", "input", "L", 3), ("C1", "input", "L", 5), ("C2", "input", "L", 7),
            ("H1", "passive", "L", 9), ("H2", "passive", "L", 11), ("Q1", "output", "R", 1), ("QN1", "output", "R", 3),
            ("Q2", "output", "R", 5), ("QN2", "output", "R", 7)]
nets = {"D1": "D1", "D2": "Q1", "C1": "CK", "C2": "CK", "H1": "+6.3V", "H2": "GND",
        "Q1": "Q1", "QN1": "QN1", "Q2": "Q2", "QN2": "QN2"}
sh.subsheet("DUT", "DFFP2_J2N16.kicad_sch", (125*G, 30*G), (14*G, 13*G), dut_pins, nets, [(PROJ, f"/{ROOT}", "2")], DUT)
# outputs: one divider each -> load tubes (both grids on the LV net, plates through 10k)
y = 12*G
for o, ng in tb['outputs'].items():
    divider(sh, 160*G, y + 4*G, o, f"{o}_LV", pf(3.9 * ng))
    for i in range(ng // 2):
        t = sh.ref("Л"); xx = 195*G + i * 32*G
        sh.part(N16, (xx, y + 6*G), None, "6Н16Б", {"1": f"PL_{o}{i}a", "7": f"{o}_LV", **n16_bottom("+6.3V", "GND")},
                unit=1, props=SIM[N16], refs=t)
        sh.part(N16, (xx + 12*G, y + 6*G), None, "6Н16Б", {"5": f"PL_{o}{i}b", "3": f"{o}_LV", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
        sh.part("Device:R", (xx - 5*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}a"})
        sh.part("Device:R", (xx + 18*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}b"})
    y += 26*G
yt = y + 4*G
sh.text(".options method=gear\n.tran 5n %gu" % round(tb['stop'], 3), (20*G, yt), 1.5)
sh.text(f"{tb['name']} testbench (tools/kicad/gen_dffp_j2n16.py, stimulus, part values and .meas from tools/spice/pff_tb.py).\n"
        "STIM_D (HV PWL, ideal) -> divider -> driver triode (Ra 10k): its plate is the HV net D1. CK: the HV clock line, 30 ns edges.\n"
        "The two flip-flops form a shift register: Q1 drives D2 and a divider with 4 grids; QN1, Q2, QN2 a divider with 6 grids each.\n"
        + tb['note'] + "\nThe plain-SPICE run of the same bench: python3 tools/spice/pff_tb.py", (20*G, yt + 6*G))
sh.text("\n".join("." + l for l in tb['meas']), (20*G, yt + 15*G), 1.0)
sh.dump(os.path.join(OUT, CELL, f"{PROJ}.kicad_sch"), f"{tb['name']} testbench", root=True,
        comments=["HV +150/+50 V, LV +10/-20 V", tb["note"][:120]], paper="A1")
open(os.path.join(OUT, CELL, f"{PROJ}.kicad_pro"), "w").write(
    '{\n  "meta": {\n    "filename": "%s.kicad_pro",\n    "version": 3\n  }\n}\n' % PROJ)
print("ok")
