#!/usr/bin/env python3
"""Generate the RSLATCH_J2N16, DLATCH2_J2N16 and DFF_J2N16 sheets and their testbenches
(doc/cell_design_method.md, sch/logic/RSLATCH_J2N16/README.md).

usage: gen_latch_j2n16.py OUT_DIR
  OUT_DIR/RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch   cell: gated RS latch, 2 x 6Zh2B + 1 x 6N16B (sub-sheet of the two below)
  OUT_DIR/DLATCH2_J2N16/DLATCH2_J2N16.kicad_sch   two D latches: 2 x RSLATCH + one 6N16B for both D inverters (7 tubes)
  OUT_DIR/DFF_J2N16/DFF_J2N16.kicad_sch       master-slave D flip-flop, falling edge: 2 x RSLATCH + one 6N16B (D and C) (7 tubes)
  OUT_DIR/<cell>/<cell>_tb.kicad_sch/.kicad_pro   testbenches; stimulus, loads and .meas from tools/spice/latch_tb.py

Unlike gen_nand2_j2.py the parts are connected by net labels at short pin stubs, not by drawn wires: the cells have
many internal nets, and the labels carry the same names as the plain-SPICE reference (latch_tb.py).
Every run makes new UUIDs: regenerate to start over, edit drawn sheets in KiCad. RSLATCH_J2N16.kicad_sch carries
the instances of all three testbench projects.
"""
import sys, os

OUT = sys.argv[1]
for _c in ("RSLATCH_J2N16", "DLATCH2_J2N16", "DFF_J2N16"): os.makedirs(os.path.join(OUT, _c), exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from kicad_sheet import *  # noqa: E402,F401,F403
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import latch_tb as TB  # noqa: E402


# ================================================================ the cells
P = TB.P
RA, RG2, CB = "10k", "15k", "%dp" % P['Cb']
C1F, C1P, C1G3 = pf(P['C1f']), pf(P['C1p']), P['C1g3']

# sheet uuids of the testbench roots and of every sheet instance, fixed before any file is written
R = {k: U() for k in ("rs", "dl", "df")}
S = {k: U() for k in ("rs_dut", "dl_dut", "df_dut", "dl_l1", "dl_l2", "df_m", "df_s")}
PROJ = {"rs": "RSLATCH_J2N16_tb", "dl": "DLATCH2_J2N16_tb", "df": "DFF_J2N16_tb"}

# ---------------------------------------------------------------- RSLATCH_J2N16
rs_insts = [(PROJ["rs"], f"/{R['rs']}/{S['rs_dut']}", 1),
            (PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}/{S['dl_l1']}", 1), (PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}/{S['dl_l2']}", 2),
            (PROJ["df"], f"/{R['df']}/{S['df_dut']}/{S['df_m']}", 1), (PROJ["df"], f"/{R['df']}/{S['df_dut']}/{S['df_s']}", 2)]
rs = Sheet(rs_insts)
H = {"S": "input", "R": "input", "E": "input", "Q": "output", "QN": "output", "H1": "passive", "H2": "passive"}
x0, y0 = 30*G, 30*G
# QN half: pentode (S on g1, E on g3) and triode A (grid from Q) on the plate QN; Q half mirrored
rs.part(J2, (x0, y0), "Л", "6Ж2Б", {"1": "QN", "2": "E", "3": "SG1", "7": "S", **j2_bottom()}, props=SIM[J2], hier=H)
rs.part(J2, (x0, y0 + 30*G), "Л", "6Ж2Б", {"1": "Q", "2": "E", "3": "SG2", "7": "R", **j2_bottom()}, props=SIM[J2], hier=H)
tref = rs.ref("Л")
rs.part(N16, (x0 + 25*G, y0), None, "6Н16Б", {"1": "QN", "7": "FQ", **n16_bottom()}, unit=1, props=SIM[N16], hier=H, refs=tref)
rs.part(N16, (x0 + 25*G, y0 + 30*G), None, "6Н16Б", {"5": "Q", "3": "FQN", "2": "GND"}, unit=2, props=SIM[N16], hier=H, refs=tref)
# plate and screen resistors, Cb on each g3 (to -50 V, as in latch_sweep.py)
rs.part("Device:R", (x0 + 40*G, y0 - 6*G), "R", RA, {"1": "+150V", "2": "QN"}, hier=H)
rs.part("Device:R", (x0 + 40*G, y0 + 24*G), "R", RA, {"1": "+150V", "2": "Q"}, hier=H)
rs.part("Device:R", (x0 + 12*G, y0 - 6*G), "R", RG2, {"1": "+150V", "2": "SG1"}, hier=H)
rs.part("Device:R", (x0 + 12*G, y0 + 24*G), "R", RG2, {"1": "+150V", "2": "SG2"}, hier=H)
rs.part("Device:C", (x0 - 12*G, y0 + 10*G), "C", CB, {"1": "E", "2": "-50V"}, hier=H)
rs.part("Device:C", (x0 - 12*G, y0 + 40*G), "C", CB, {"1": "E", "2": "-50V"}, hier=H)
# cross-coupling dividers: Q -> FQ (grid of triode A), QN -> FQN (grid of triode B)
divider(rs, x0 + 50*G, y0 + 2*G, "Q", "FQ", C1F, hier=H)
divider(rs, x0 + 50*G, y0 + 32*G, "QN", "FQN", C1F, hier=H)
rs.text("RSLATCH_J2N16: gated RS latch. QN = ~((S & E) | Q), Q = ~((R & E) | QN).\n"
        "Two AND-OR-INVERT halves: 6Zh2B (S or R on g1, E on g3) and one triode of the 6N16B on a common plate, Ra 10k.\n"
        "Each plate drives the other half's triode through a divider in the cell (470k || 3.9 pF / 200k to -50 V).\n"
        "S, R, E: LV (1 = +10 V, 0 = -20 V). Q, QN: HV (1 = +150 V, 0 = +50 V). S = R = 1 with E = 1 is forbidden (Q = QN = 0).\n"
        "Screens Rg2 15k from +150 V; Cb 15 pF on each g3 holds E against the plate swing (g3 Miller, sch/logic/NAND2_J2/README.md).\n"
        "Input divider C1 per grid: S, R (pentode g1) 2.7 pF; E (two g3) 2 x 6.8 pF. Outputs: one divider per net, 3.9 pF per triode grid.\n"
        "Simulated, fanout 2/10: E -> Q 172/368 ns, S -> QN 138/337 ns; E pulse >= 216/454 ns; setup 182/432 ns, hold <= 0.\n"
        "Heater 6.3 V: 2 x 0.2 A + 0.4 A on H1/H2. Page: sch/logic/RSLATCH_J2N16/README.md", (20*G, 85*G))
rs.dump(os.path.join(OUT, "RSLATCH_J2N16", "RSLATCH_J2N16.kicad_sch"), "RSLATCH_J2N16 - gated RS latch",
        comments=["QN = ~((S&E)|Q), Q = ~((R&E)|QN); S, R, E: LV; Q, QN: HV", "2 x 6Zh2B + 6N16B; Ra 10k, Rg2 15k, Cb 15p"], paper="A3")

RS_PINS = [("S", "input", "L", 1), ("R", "input", "L", 3), ("E", "input", "L", 5), ("H1", "passive", "L", 8),
           ("H2", "passive", "L", 9), ("Q", "output", "R", 1), ("QN", "output", "R", 3)]
RS_SIZE = (14*G, 11*G)


def inverter_tube(sh, nets1, nets2, hier, x, y):
    """one 6N16B as two inverters with Ra 10k: nets = (grid, plate)"""
    t = sh.ref("Л")
    sh.part(N16, (x, y), None, "6Н16Б", {"1": nets1[1], "7": nets1[0], **n16_bottom()}, unit=1, props=SIM[N16], hier=hier, refs=t)
    sh.part(N16, (x, y + 25*G), None, "6Н16Б", {"5": nets2[1], "3": nets2[0], "2": "GND"}, unit=2, props=SIM[N16], hier=hier, refs=t)
    sh.part("Device:R", (x + 12*G, y - 6*G), "R", "10k", {"1": "+150V", "2": nets1[1]}, hier=hier)
    sh.part("Device:R", (x + 12*G, y + 19*G), "R", "10k", {"1": "+150V", "2": nets2[1]}, hier=hier)


# ---------------------------------------------------------------- DLATCH2_J2N16
dl = Sheet([(PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}", 9)])
HD = {"D1": "input", "D2": "input", "E": "input", "Q1": "output", "QN1": "output", "Q2": "output", "QN2": "output",
      "H1": "passive", "H2": "passive"}
inverter_tube(dl, ("D1", "DN1"), ("D2", "DN2"), HD, 25*G, 25*G)
divider(dl, 45*G, 27*G, "DN1", "R1", C1P, hier=HD)
divider(dl, 45*G, 52*G, "DN2", "R2", C1P, hier=HD)
for i, (uid, yy) in enumerate(((S['dl_l1'], 20*G), (S['dl_l2'], 45*G)), 1):
    nets = {"S": f"D{i}", "R": f"R{i}", "E": "E", "Q": f"Q{i}", "QN": f"QN{i}", "H1": "H1", "H2": "H2"}
    dl.subsheet(f"L{i}", "../RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch", (90*G, yy), RS_SIZE, RS_PINS, nets,
                [(PROJ["dl"], f"/{R['dl']}/{S['dl_dut']}", str(2 + i))], uid, hier=HD)
dl.text("DLATCH2_J2N16: two D latches, Qi = Di while E = 1, held while E = 0. 7 tubes: 2 x RSLATCH_J2N16 + one 6N16B.\n"
        "The 6N16B inverts D1 and D2 (Ra 10k), each through a divider (2.7 pF, one pentode g1) to R of its latch.\n"
        "D pins: one pentode g1 + one triode grid (divider C1 2.7 + 3.9 pF). E: four g3 (4 x 6.8 pF). Outputs HV.\n"
        "A 16-tube board holds two of these (four latches) or two DFF_J2N16. Page: sch/logic/RSLATCH_J2N16/README.md", (20*G, 80*G))
dl.dump(os.path.join(OUT, "DLATCH2_J2N16", "DLATCH2_J2N16.kicad_sch"), "DLATCH2_J2N16 - two D latches",
        comments=["Qi = Di while E = 1; D, E: LV; Q, QN: HV", "2 x RSLATCH_J2N16 + 6N16B (D inverters)"], paper="A3")

# ---------------------------------------------------------------- DFF_J2N16
df = Sheet([(PROJ["df"], f"/{R['df']}/{S['df_dut']}", 9)])
HF = {"D": "input", "C": "input", "Q": "output", "QN": "output", "H1": "passive", "H2": "passive"}
inverter_tube(df, ("D", "DN"), ("C", "CN"), HF, 25*G, 25*G)
divider(df, 45*G, 27*G, "DN", "RM", C1P, hier=HF)
divider(df, 45*G, 52*G, "CN", "ES", pf(2 * C1G3), hier=HF)
divider(df, 125*G, 22*G, "QM", "SS", C1P, hier=HF)
divider(df, 125*G, 32*G, "QNM", "RS", C1P, hier=HF)
df.subsheet("M", "../RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch", (90*G, 20*G), RS_SIZE,
            RS_PINS, {"S": "D", "R": "RM", "E": "C", "Q": "QM", "QN": "QNM", "H1": "H1", "H2": "H2"},
            [(PROJ["df"], f"/{R['df']}/{S['df_dut']}", "3")], S['df_m'], hier=HF)
df.subsheet("S", "../RSLATCH_J2N16/RSLATCH_J2N16.kicad_sch", (90*G, 50*G), RS_SIZE,
            RS_PINS, {"S": "SS", "R": "RS", "E": "ES", "Q": "Q", "QN": "QN", "H1": "H1", "H2": "H2"},
            [(PROJ["df"], f"/{R['df']}/{S['df_dut']}", "4")], S['df_s'], hier=HF)
df.text("DFF_J2N16: master-slave D flip-flop, Q takes D at the FALLING edge of C (owner's drawing, 2026-10-27).\n"
        "Master M = RSLATCH (S = D, R = ~D, E = C): transparent while C = 1. Slave S = RSLATCH (S = QM, R = QNM, E = ~C).\n"
        "One 6N16B: D -> DN (divider 2.7 pF -> RM), C -> CN (divider 2 x 6.8 pF -> ES). QM, QNM -> SS, RS through 2.7 pF dividers.\n"
        "The C inverter must stay in the cell: the master opens before the slave closes by its delay, race margin ~90 ns.\n"
        "Simulated: register to register 1.11 / 1.05 / 0.93 MHz at fanout 2 / 6 / 10; C -> Q 340/539 ns (fanout 2/10); hold <= 0.\n"
        "D: one pentode g1 + one triode grid (C1 2.7 + 3.9 pF). C: two g3 + one triode grid (2 x 6.8 + 3.9 pF). 7 tubes, heater 2.0 A.\n"
        "Page: sch/logic/RSLATCH_J2N16/README.md", (20*G, 80*G))
df.dump(os.path.join(OUT, "DFF_J2N16", "DFF_J2N16.kicad_sch"), "DFF_J2N16 - D flip-flop, falling edge",
        comments=["Q <= D at the falling edge of C; D, C: LV; Q, QN: HV", "2 x RSLATCH_J2N16 + 6N16B (D and C inverters)"], paper="A3")


# ================================================================ testbenches
def testbench(key, tb, cell_file, cell_pins, size):
    proj = PROJ[key]
    sh = Sheet([(proj, f"/{R[key]}", "")], uid=R[key])
    # supplies
    x = 10*G
    for i, (v, top, bot, y) in enumerate((("150", "+150V", "GND", 15*G), ("50", "GND", "-50V", 35*G), ("6.3", "+6.3V", "GND", 55*G))):
        props = {"Sim.Device": "V", "Sim.Type": "DC", "Sim.Pins": "1=+ 2=-", "Sim.Params": f"dc={v}"}
        rf = sh.ref("V")
        sh.symbol("Simulation_SPICE:VDC", (x, y), 0, rf, v, props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
        for pin, net in (("1", top), ("2", bot)):
            p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, pin)
            e = (p[0], p[1] + d[1] * G)
            sh.wire(p, e); sh.power(net, e, d)
            if net != "GND" or v == "150":
                fp = (e[0] + 3*G, e[1]); sh.wire(e, fp)
                sh.symbol("power:PWR_FLAG", fp, 0, sh.ref("#FLG"), "PWR_FLAG", ref_off=(0, -1.905), val_off=(1.27, -3.81), hide_ref=True, pins=["1"])
    # drivers: PWL source -> divider -> 6N16B triode (Ra 10k; second triode cut off, grid at -50 V) -> divider -> input
    y = 12*G
    for k, (times, bits) in tb['src'].items():
        pts = " ".join(f"{t:.4f}u {v}" for t, v in TB.pwl_pts(times, bits))
        props = {"Sim.Device": "V", "Sim.Type": "PWL", "Sim.Pins": "1=+ 2=-", "Sim.Params": f'pwl="{pts}"'}
        sh.part("Simulation_SPICE:VPWL", (30*G, y + 4*G), "V", "VPWL", {"1": f"STIM_{k}", "2": "GND"}, props=props)
        divider(sh, 38*G, y + 4*G, f"STIM_{k}", f"IS_{k}", pf(P['C1g']))
        t = sh.ref("Л")
        sh.part(N16, (75*G, y + 6*G), None, "6Н16Б", {"1": f"PD_{k}", "7": f"IS_{k}", **n16_bottom("+6.3V", "GND")},
                unit=1, props=SIM[N16], refs=t)
        sh.part(N16, (88*G, y + 6*G), None, "6Н16Б", {"5": f"PDX_{k}", "3": "-50V", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
        sh.part("Device:R", (65*G, y + 2*G), "R", "10k", {"1": "+150V", "2": f"PD_{k}"})
        sh.part("Device:R", (98*G, y + 2*G), "R", "10k", {"1": "+150V", "2": f"PDX_{k}"})
        divider(sh, 104*G, y + 4*G, f"PD_{k}", k, pf(tb['inputs'][k]))
        y += 26*G
    # DUT
    nets = {n: n for n, *_ in cell_pins}; nets.update(H1="+6.3V", H2="GND")
    sh.subsheet("DUT", cell_file, (150*G, 20*G), size, cell_pins, nets, [(proj, f"/{R[key]}", "2")], S[key + "_dut"])
    # outputs: one divider each -> load tubes (both grids on the LV net, plates through 10k)
    y = 12*G
    for o, ng in tb['outputs'].items():
        divider(sh, 185*G, y + 4*G, o, f"{o}_LV", pf(P['C1g'] * ng))
        for i in range(ng // 2):
            t = sh.ref("Л"); xx = 220*G + i * 26*G
            sh.part(N16, (xx, y + 6*G), None, "6Н16Б", {"1": f"PL_{o}{i}a", "7": f"{o}_LV", **n16_bottom("+6.3V", "GND")},
                    unit=1, props=SIM[N16], refs=t)
            sh.part(N16, (xx + 12*G, y + 6*G), None, "6Н16Б", {"5": f"PL_{o}{i}b", "3": f"{o}_LV", "2": "GND"}, unit=2, props=SIM[N16], refs=t)
            sh.part("Device:R", (xx - 5*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}a"})
            sh.part("Device:R", (xx + 18*G, y - 2*G), "R", "10k", {"1": "+150V", "2": f"PL_{o}{i}b"})
        y += 26*G
    yt = max(y, 12*G + 26*G * len(tb['src'])) + 4*G
    sh.text(".tran 5n %gu" % round(tb['stop'], 3), (20*G, yt), 1.5)
    sh.text(f"{tb['name']} testbench (tools/kicad/gen_latch_j2n16.py, stimulus and .meas from tools/spice/latch_tb.py).\n"
            "STIM_x (HV PWL, ideal) -> divider -> driver triode (Ra 10k) -> divider -> x (LV DUT input): real edges and levels.\n"
            "Each output -> one divider (C1 3.9 pF per grid) -> x_LV -> load tubes, both grids on the net.\n"
            + tb['note'] + "\nThe plain-SPICE run of the same bench: python3 tools/spice/latch_tb.py", (20*G, yt + 3*G))
    sh.text("\n".join("." + l for l in tb['meas']), (20*G, yt + 12*G), 1.0)
    sh.dump(os.path.join(OUT, tb["name"], f"{tb['name']}_tb.kicad_sch"), f"{tb['name']} testbench", root=True,
            comments=["HV +150/+50 V, LV +10/-20 V", tb["note"][:120]], paper="A1")
    open(os.path.join(OUT, tb["name"], f"{tb['name']}_tb.kicad_pro"), "w").write(
        '{\n  "meta": {\n    "filename": "%s_tb.kicad_pro",\n    "version": 3\n  }\n}\n' % tb['name'])

testbench("rs", TB.rslatch_tb(), "RSLATCH_J2N16.kicad_sch", RS_PINS, RS_SIZE)
testbench("dl", TB.dlatch2_tb(), "DLATCH2_J2N16.kicad_sch",
          [("D1", "input", "L", 1), ("D2", "input", "L", 3), ("E", "input", "L", 5), ("H1", "passive", "L", 8),
           ("H2", "passive", "L", 9), ("Q1", "output", "R", 1), ("QN1", "output", "R", 3), ("Q2", "output", "R", 5),
           ("QN2", "output", "R", 7)], (14*G, 11*G))
testbench("df", TB.dff_tb(), "DFF_J2N16.kicad_sch",
          [("D", "input", "L", 1), ("C", "input", "L", 3), ("H1", "passive", "L", 8), ("H2", "passive", "L", 9),
           ("Q", "output", "R", 1), ("QN", "output", "R", 3)], (14*G, 11*G))
print("ok")
