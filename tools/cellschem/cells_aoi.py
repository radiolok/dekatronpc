"""NAND2_J2, A1OOI_N16J2, AOI211_J2N16, A2OOI_J2.

6Zh2B pentode: A on g1 (pin 7), B on g3 (pin 2), screen g2 (pin 3) from +150 V
through Rg2 15k. It conducts to the plate only when g1 and g3 are both high
(AND). Cb 15 pF on g3 holds B against the plate swing (g3 Miller, see the
NAND2_J2 README). 6N16B triodes on the same plate add the OR terms."""
from lib import Sch

LEVELS = "LV (grids): 1 = +10 V, 0 = −20 V.   HV (plates): 1 = +150 V, 0 = +50 V.   Ra = Rg2 = 15k."
HEATER = "Heater 6.3 V on H1/H2 (6Zh2B pins 4, 5; 6N16B pins 8, 4), all tubes in parallel, not drawn."
DY = 300          # row pitch of two-row sheets


def _pent(s, cx, cy, ref, in1, in3, cb, rg, nm, flip=False, in3_sub=None):
    """Pentode with input pins, Cb on g3 and the screen resistor hanging from +150 V.

    flip=True mirrors it: inputs on the right, screen on the left."""
    m = -1 if flip else 1
    p = s.pentode(cx, cy, ref, flip=flip)
    gx = p["g1"][0]
    px = gx - 58 * m
    s.pin_in(px, p["g1"][1], in1, right=flip)
    s.wire([(px, p["g1"][1]), p["g1"]])
    s.pin_in(px, p["g3"][1], in3, sub=in3_sub, right=flip)
    s.wire([(px, p["g3"][1]), p["g3"]], net="b" + nm)
    tx = gx - 30 * m                  # Cb tap on the B wire, up to its supply bar
    s.dot(tx, p["g3"][1])
    s.cap_v(tx, p["g3"][1], p["g3"][1] - 56, cb[0], cb[1], side="right" if flip else "left")
    s.vcc(tx, p["g3"][1] - 56, cb[2])
    sx = p["g2"][0] + 30 * m          # screen: Rg2 from a local +150 V
    s.wire([p["g2"], (sx, p["g2"][1])])
    s.res_v(sx, p["g2"][1] - 92, p["g2"][1], rg[0], "15k")
    s.vcc(sx, p["g2"][1] - 92, "+150 V")
    s.gnd(*p["k"])
    return p


def _ra(s, rail_y, x, bus_y, ref, val="15k"):
    s.res_v(x, rail_y, bus_y, ref, val)
    s.dot(x, rail_y)


def nand2_j2():
    s = Sch(660, 440, "NAND2_J2", "Y = ~(A · B)  ·  one 6Zh2B pentode",
            ["Y falls only when both g1 and g3 are high; the pentode current is the plate pull-down.",
             LEVELS, HEATER])
    s.rail(80, 130, 600, "+150 V")
    cx, cy, bus = 330, 290, 160
    p = _pent(s, cx, cy, "Л1", "A", "B", ("C11", "15p", "GND"), ("R12",), "1")
    s.res_v(cx, 80, bus, "R11", "15k")
    s.dot(cx, 80)
    s.wire([(cx, bus), p["a"]])
    s.dot(cx, bus)
    s.wire([(cx, bus), (cx + 160, bus)])
    s.pin_out(cx + 160, bus, "Y")
    return s


def a1ooi_n16j2():
    s = Sch(700, 780, "A1OOI_N16J2",
            "Yi = ~((Ai · Bi) + Ci), two cells (AOI21)  ·  two 6Zh2B + one 6N16B",
            ["Л103 is one 6N16B bulb: Л103a is the OR input of cell 1, Л103b of cell 2.",
             LEVELS, HEATER])
    for i in range(2):
        y = i * DY
        n = str(i + 1)
        s.rail(80 + y, 120, 640, "+150 V")
        cy, bus = 290 + y, 160 + y
        tcx, pcx = 190, 450
        t = s.triode(tcx, cy, "Л103" + "ab"[i], ("1", "7", "6") if i == 0 else ("5", "3", "2"))
        s.pin_in(t["g"][0] - 20, cy, "C" + n)
        s.wire([(t["g"][0] - 20, cy), t["g"]])
        s.gnd(*t["k"])
        p = _pent(s, pcx, cy, "Л10" + n, "A" + n, "B" + n,
                  ("C10" + n, "15p", "−50 V"), ("R10" + str(i + 1),), n)
        s.wire([t["a"], (tcx, bus), (pcx, bus), p["a"]], net="y" + n)
        s.dot(tcx, bus)
        s.dot(pcx, bus)
        rx = 320
        s.res_v(rx, 80 + y, bus, "R10" + str(i + 3), "15k")
        s.dot(rx, 80 + y)
        s.dot(rx, bus)
        s.wire([(tcx, bus), (110, bus)], net="y" + n)
        s.pin_out(110, bus, "Y" + n, left=True)
    return s


def aoi211_j2n16():
    s = Sch(780, 440, "AOI211_J2N16", "Y = ~((A · B) + C + D)  ·  one 6Zh2B + one 6N16B",
            ["The two triodes of Л102 are the OR inputs C and D on the pentode's plate.", LEVELS, HEATER])
    s.rail(80, 100, 720, "+150 V")
    cy, bus = 290, 160
    s.group(115, cy - 70, 340, 150, "Л102 · 6N16B")
    t1 = s.triode(200, cy, "Л102a", ("1", "7", "6"))
    t2 = s.triode(370, cy, "Л102b", ("5", "3", "2"))
    for nm, t in (("C", t1), ("D", t2)):
        s.pin_in(t["g"][0] - 22, cy, nm)
        s.wire([(t["g"][0] - 22, cy), t["g"]])
        s.gnd(*t["k"])
    pcx = 610
    p = _pent(s, pcx, cy, "Л101", "A", "B", ("C101", "15p", "−50 V"), ("R101",), "1")
    s.wire([t1["a"], (200, bus), (pcx, bus), p["a"]], net="y")
    s.wire([t2["a"], (370, bus)], net="y")
    s.dot(200, bus)
    s.dot(370, bus)
    s.dot(pcx, bus)
    s.res_v(285, 80, bus, "R102", "15k")
    s.dot(285, 80)
    s.dot(285, bus)
    s.wire([(200, bus), (120, bus)], net="y")
    s.pin_out(120, bus, "Y", left=True)
    return s


def a2ooi_j2():
    s = Sch(860, 440, "A2OOI_J2", "Y = ~((A · B) + (C · D))  ·  two 6Zh2B on one plate",
            ["Either pentode pulls Y down when its own g1 and g3 are both high.", LEVELS, HEATER])
    s.rail(80, 100, 800, "+150 V")
    cy, bus = 290, 160
    p1 = _pent(s, 250, cy, "Л101", "A", "B", ("C101", "15p", "−50 V"), ("R101",), "1")
    p2 = _pent(s, 600, cy, "Л102", "C", "D", ("C102", "15p", "−50 V"), ("R102",), "2")
    s.wire([p1["a"], (250, bus), (600, bus), p2["a"]], net="y")
    s.dot(250, bus)
    s.dot(600, bus)
    rx = 425
    s.res_v(rx, 80, bus, "R103", "15k")
    s.dot(rx, 80)
    s.dot(rx, bus)
    s.wire([(600, bus), (760, bus)], net="y")
    s.pin_out(760, bus, "Y")
    return s
