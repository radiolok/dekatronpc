#!/usr/bin/env python3
"""Generate the A1OOI_N16J2, A2OOI_J2 and NOR4_N16 cell sheets and their testbenches (doc/cell_design_method.md,
sch/logic/A1OOI_N16J2/README.md, sch/logic/A2OOI_J2/README.md).

usage: gen_aoi.py OUT_DIR
  OUT_DIR/A1OOI_N16J2/A1OOI_N16J2.kicad_sch   two AOI21 cells: 2 x 6Zh2B + one 6N16B (one triode per cell)
  OUT_DIR/A2OOI_J2/A2OOI_J2.kicad_sch         one AOI22 cell: 2 x 6Zh2B on one plate
  OUT_DIR/NOR4_N16/NOR4_N16.kicad_sch         four-input NOR: 2 x 6N16B, all plates on Y
  OUT_DIR/<cell>/<cell>_tb.kicad_sch/.kicad_pro   testbenches; stimulus, loads and .meas from tools/spice/aoi_tb.py

Parts are connected by net labels at short pin stubs (kicad_sheet.py, as gen_latch_j2n16.py).
Every run makes new UUIDs: regenerate to start over, edit drawn sheets in KiCad.
"""
import sys, os

OUT = sys.argv[1]
for _c in ("A1OOI_N16J2", "A2OOI_J2", "NOR4_N16"): os.makedirs(os.path.join(OUT, _c), exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from kicad_sheet import *  # noqa: E402,F401,F403
sys.path.insert(0, os.path.join(REPO, "tools", "spice"))
import aoi_tb as TB  # noqa: E402
import latch_tb as LTB  # noqa: E402

P = TB.P
RA, RG2, CB = P['Ra'], P['Rg2'], "%dp" % P['Cb']

R = {k: U() for k in ("a1", "a22", "n4")}           # testbench root sheets
S = {k: U() for k in ("a1", "a22", "n4")}           # the DUT sheet instance in each
PROJ = {"a1": "A1OOI_N16J2_tb", "a22": "A2OOI_J2_tb", "n4": "NOR4_N16_tb"}


def pentode(sh, x, y, g1, g3, plate, screen, hier):
    """6Zh2B with its screen resistor and the Cb of g3"""
    sh.part(J2, (x, y), "Л", "6Ж2Б", {"1": plate, "2": g3, "3": screen, "7": g1, **j2_bottom()}, props=SIM[J2], hier=hier)
    sh.part("Device:R", (x + 12*G, y - 6*G), "R", RG2, {"1": "+150V", "2": screen}, hier=hier)
    sh.part("Device:C", (x - 12*G, y + 10*G), "C", CB, {"1": g3, "2": "-50V"}, hier=hier)


# ---------------------------------------------------------------- A1OOI_N16J2: two cells on one 6N16B
a1 = Sheet([(PROJ["a1"], f"/{R['a1']}/{S['a1']}", 1)])
H1 = {"A1": "input", "B1": "input", "C1": "input", "A2": "input", "B2": "input", "C2": "input",
      "Y1": "output", "Y2": "output", "H1": "passive", "H2": "passive"}
x0, y0 = 30*G, 30*G
pentode(a1, x0, y0, "A1", "B1", "Y1", "SG1", H1)
pentode(a1, x0, y0 + 30*G, "A2", "B2", "Y2", "SG2", H1)
t = a1.ref("Л")
a1.part(N16, (x0 + 25*G, y0), None, "6Н16Б", {"1": "Y1", "7": "C1", **n16_bottom()}, unit=1, props=SIM[N16], hier=H1, refs=t)
a1.part(N16, (x0 + 25*G, y0 + 30*G), None, "6Н16Б", {"5": "Y2", "3": "C2", "2": "GND"}, unit=2, props=SIM[N16], hier=H1, refs=t)
a1.part("Device:R", (x0 + 40*G, y0 - 6*G), "R", RA, {"1": "+150V", "2": "Y1"}, hier=H1)
a1.part("Device:R", (x0 + 40*G, y0 + 24*G), "R", RA, {"1": "+150V", "2": "Y2"}, hier=H1)
a1.text("A1OOI_N16J2: two AND-OR-INVERT cells (AOI21), Yi = ~((Ai & Bi) | Ci). 3 tubes = 2 cells (liberty: 1.5 per cell).\n"
        "Each cell: 6Zh2B (Ai on g1, Bi on g3) and one triode of the shared 6N16B (Ci on the grid) on one plate, Ra 15k.\n"
        "Screens Rg2 15k from +150 V; Cb 15 pF on each g3 holds B against the plate swing (g3 Miller, sch/logic/NAND2_J2/README.md).\n"
        "A, B, C: LV (1 = +10 V, 0 = -20 V). Y: HV (1 = +150 V, 0 = +50 V); one divider per output net, 3.9 pF per triode grid.\n"
        "Input divider C1 per grid: A (pentode g1) 2.7 pF, B (g3) 6.8 pF, C (triode) 3.9 pF. An unused cell: inputs on an LV 0.\n"
        "Simulated, fanout 2/6/10: worst arc 194/312/420 ns, C rising alone 53/61/66 ns.\n"
        "Heater 6.3 V: 2 x 0.2 A + 0.4 A on H1/H2. Page: sch/logic/A1OOI_N16J2/README.md", (20*G, 85*G))
a1.dump(os.path.join(OUT, "A1OOI_N16J2", "A1OOI_N16J2.kicad_sch"), "A1OOI_N16J2 - 2 x AOI21",
        comments=["Yi = ~((Ai&Bi)|Ci); A, B, C: LV; Y: HV", "2 x 6Zh2B + 6N16B; Ra 15k, Rg2 15k, Cb 15p"], paper="A3")
A1_PINS = [("A1", "input", "L", 1), ("B1", "input", "L", 3), ("C1", "input", "L", 5), ("A2", "input", "L", 8),
           ("B2", "input", "L", 10), ("C2", "input", "L", 12), ("H1", "passive", "L", 15), ("H2", "passive", "L", 16),
           ("Y1", "output", "R", 3), ("Y2", "output", "R", 10)]
A1_SIZE = (14*G, 18*G)

# ---------------------------------------------------------------- A2OOI_J2: AOI22
a2 = Sheet([(PROJ["a22"], f"/{R['a22']}/{S['a22']}", 1)])
H2 = {"A": "input", "B": "input", "C": "input", "D": "input", "Y": "output", "H1": "passive", "H2": "passive"}
pentode(a2, x0, y0, "A", "B", "Y", "SG1", H2)
pentode(a2, x0, y0 + 30*G, "C", "D", "Y", "SG2", H2)
a2.part("Device:R", (x0 + 25*G, y0 - 6*G), "R", RA, {"1": "+150V", "2": "Y"}, hier=H2)
a2.text("A2OOI_J2: AND-OR-INVERT (AOI22), Y = ~((A & B) | (C & D)). Two 6Zh2B on one plate, Ra 15k.\n"
        "A, C on g1; B, D on g3. Screens Rg2 15k from +150 V; Cb 15 pF on each g3 (g3 Miller, sch/logic/NAND2_J2/README.md).\n"
        "A, B, C, D: LV (1 = +10 V, 0 = -20 V). Y: HV (1 = +150 V, 0 = +50 V); one divider per output net.\n"
        "Input divider C1 per grid: A, C (pentode g1) 2.7 pF; B, D (g3) 6.8 pF.\n"
        "Simulated, fanout 2/6/10: worst arc 209/326/418 ns. Heater 6.3 V: 2 x 0.2 A on H1/H2.\n"
        "Page: sch/logic/A2OOI_J2/README.md", (20*G, 85*G))
a2.dump(os.path.join(OUT, "A2OOI_J2", "A2OOI_J2.kicad_sch"), "A2OOI_J2 - AOI22",
        comments=["Y = ~((A&B)|(C&D)); A-D: LV; Y: HV", "2 x 6Zh2B; Ra 15k, Rg2 15k, Cb 15p"], paper="A3")
A2_PINS = [("A", "input", "L", 1), ("B", "input", "L", 3), ("C", "input", "L", 5), ("D", "input", "L", 7),
           ("H1", "passive", "L", 10), ("H2", "passive", "L", 11), ("Y", "output", "R", 3)]
A2_SIZE = (14*G, 13*G)


# ---------------------------------------------------------------- NOR4_N16: two 6N16B, four triodes on one plate
n4 = Sheet([(PROJ["n4"], f"/{R['n4']}/{S['n4']}", 1)])
H4 = {"A": "input", "B": "input", "C": "input", "D": "input", "Y": "output", "H1": "passive", "H2": "passive"}
for k, (ga, gb) in enumerate((("A", "B"), ("C", "D"))):
    t = n4.ref("Л"); yy = y0 + 30*G * k
    n4.part(N16, (x0, yy), None, "6Н16Б", {"1": "Y", "7": ga, **n16_bottom()}, unit=1, props=SIM[N16], hier=H4, refs=t)
    n4.part(N16, (x0 + 25*G, yy), None, "6Н16Б", {"5": "Y", "3": gb, "2": "GND"}, unit=2, props=SIM[N16], hier=H4, refs=t)
n4.part("Device:R", (x0 + 40*G, y0 - 6*G), "R", TB.A.params("n4")['Ra'], {"1": "+150V", "2": "Y"}, hier=H4)
n4.text("NOR4_N16: four-input NOR, Y = ~(A | B | C | D). Two 6N16B, all four triode plates on Y, Ra 10k to +150 V (as NOR2_N16).\n"
        "A, B, C, D: LV (1 = +10 V, 0 = -20 V), each on a triode grid (divider C1 3.9 pF per grid). Y: HV; one divider per net.\n"
        "Simulated, fanout 2/6/10: Y falls 58-90 ns, rises 120/193/268 ns; VOL 55 V (one input) ... 27 V (all four).\n"
        "Heater 6.3 V: 2 x 0.4 A on H1/H2. Page: sch/logic/NOR4_N16/README.md", (20*G, 85*G))
n4.dump(os.path.join(OUT, "NOR4_N16", "NOR4_N16.kicad_sch"), "NOR4_N16 - 4NOR on 2 x 6N16B",
        comments=["Y = ~(A|B|C|D); A-D: LV; Y: HV", "2 x 6N16B; Ra 10k"], paper="A3")


# ================================================================ testbenches (as gen_latch_j2n16.testbench)
def testbench(key, tb, cell_file, cell_pins, size):
    proj = PROJ[key]
    sh = Sheet([(proj, f"/{R[key]}", "")], uid=R[key])
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
    if "LV0" in tb['fixed'].values():
        # LV "0" for the inputs of the unused cell: -20 V
        props = {"Sim.Device": "V", "Sim.Type": "DC", "Sim.Pins": "1=+ 2=-", "Sim.Params": "dc=20"}
        y = 75*G
        sh.symbol("Simulation_SPICE:VDC", (x, y), 0, sh.ref("V"), "20", props=props, ref_off=(3.81, -1.27), val_off=(3.81, 1.27))
        p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, "1"); e = (p[0], p[1] + d[1] * G); sh.wire(p, e); sh.power("GND", e, d)
        p, d = pin_xy("Simulation_SPICE:VDC", (x, y), 0, "2"); sh.attach(p, d, "LV0")
    y = 12*G
    for k, (times, bits) in tb['src'].items():
        pts = " ".join(f"{t:.4f}u {v}" for t, v in LTB.pwl_pts(times, bits))
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
    nets = {n: n for n, *_ in cell_pins}; nets.update(H1="+6.3V", H2="GND"); nets.update(tb['fixed'])
    sh.subsheet("DUT", cell_file, (150*G, 20*G), size, cell_pins, nets, [(proj, f"/{R[key]}", "2")], S[key])
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
    sh.text(f"{tb['name']} testbench (tools/kicad/gen_aoi.py, stimulus and .meas from tools/spice/aoi_tb.py).\n"
            "STIM_x (HV PWL, ideal) -> divider -> driver triode (Ra 10k) -> divider -> x (LV DUT input): real edges and levels.\n"
            f"The output -> one divider (C1 3.9 pF per grid) -> {list(tb['outputs'])[0]}_LV -> load tubes, both grids on the net.\n"
            + tb['note'] + f"\nThe plain-SPICE run of the same bench: python3 tools/spice/aoi_tb.py {key}", (20*G, yt + 3*G))
    sh.text("\n".join("." + l for l in tb['meas']), (20*G, yt + 12*G), 1.0)
    sh.dump(os.path.join(OUT, tb["name"], f"{tb['name']}_tb.kicad_sch"), f"{tb['name']} testbench", root=True,
            comments=["HV +150/+50 V, LV +10/-20 V", tb["note"][:120]], paper="A1")
    open(os.path.join(OUT, tb["name"], f"{tb['name']}_tb.kicad_pro"), "w").write(
        '{\n  "meta": {\n    "filename": "%s_tb.kicad_pro",\n    "version": 3\n  }\n}\n' % tb['name'])


testbench("a1", TB.tb_of("a1"), "A1OOI_N16J2.kicad_sch", A1_PINS, A1_SIZE)
testbench("a22", TB.tb_of("a22"), "A2OOI_J2.kicad_sch", A2_PINS, A2_SIZE)
testbench("n4", TB.tb_of("n4"), "NOR4_N16.kicad_sch", A2_PINS, A2_SIZE)
print("ok")
