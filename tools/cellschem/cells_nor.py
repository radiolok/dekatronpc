"""NOT_N16, NOR2_N16, NOR3_N16, NOR4_N16: 6N16B triodes on a resistive plate load."""
from lib import Sch

LEVELS = "LV (grids): 1 = +10 V, 0 = −20 V.   HV (plates): 1 = +150 V, 0 = +50 V."
HEATER = "Heater 6.3 V on H1/H2 (pins 8, 4), all tubes in parallel, not drawn."
RAIL = 80
TUBE = ("Л1 · 6N16B (two triodes, one bulb)")
CHOKE = "Plate load: Ra 10k in series with L 680 µH ‖ Rd 10k (TRS v0.58): the choke speeds up the rising edge of Y."


def _ra(s, x, y_to, ref, val):
    s.res_v(x, RAIL, y_to, ref, val)
    s.dot(x, RAIL)


def not_n16():
    s = Sch(660, 425, "NOT_N16", "Y1 = ~A1,  Y2 = ~A2  ·  one 6N16B, one triode per inverter",
            [CHOKE, LEVELS, HEATER])
    s.rail(RAIL, 150, 600, "+150 V")
    s.group(100, 190, 470, 160, TUBE)
    for i, (cx, a, y, pins, r) in enumerate(
            [(230, "A1", "Y1", ("1", "7", "6"), "R11"), (450, "A2", "Y2", ("5", "3", "2"), "R12")]):
        p = s.triode(cx, 270, "Л1" + "ab"[i], pins)
        s.plate_load(cx, RAIL, 160, (r, "10k"), ("L1" + str(i + 1), "680 µ"), ("R1" + str(i + 3), "10k"))
        s.dot(cx, RAIL)
        s.wire([(cx, 160), p["a"]])
        s.wire([(cx, 160), (cx + 70, 160)])
        s.pin_out(cx + 70, 160, y)
        s.pin_in(cx - 110, 270, a)
        s.wire([(cx - 110, 270), p["g"]])
        s.gnd(*p["k"])
    return s


def nor2_n16():
    s = Sch(680, 495, "NOR2_N16", "Y = ~(A | B)  ·  one 6N16B, both triodes in parallel on one plate",
            ["R11 10k in series with (L11 680 µH ‖ R12 10k): the choke speeds up the rising edge of Y.", LEVELS, HEATER])
    s.rail(RAIL, 150, 600, "+150 V")
    _ra(s, 340, 135, "R11", "10k")
    s.wire([(340, 135), (295, 135), (295, 155)])
    s.wire([(340, 135), (385, 135), (385, 155)])
    s.dot(340, 135)
    s.ind_v(295, 155, 245, "L11", "680 µ", side="left")
    s.res_v(385, 155, 245, "R12", "10k")
    s.wire([(295, 245), (385, 245)], net="y")
    s.dot(295, 245)
    s.dot(385, 245)
    s.group(130, 268, 420, 170, TUBE)
    p1 = s.triode(230, 355, "Л1a", ("1", "7", "6"))
    p2 = s.triode(450, 355, "Л1b", ("5", "3", "2"))
    s.wire([p1["a"], (230, 295), (450, 295), p2["a"]], net="y")
    s.wire([(340, 245), (340, 295)], net="y")
    s.dot(340, 295)
    s.dot(340, 245)
    s.wire([(385, 245), (560, 245)], net="y")
    s.pin_out(560, 245, "Y")
    s.pin_in(110, 355, "A")
    s.wire([(110, 355), p1["g"]])
    s.pin_in(375, 355, "B")
    s.wire([(375, 355), p2["g"]])
    s.gnd(*p1["k"])
    s.gnd(*p2["k"])
    return s


def nor3_n16():
    s = Sch(1110, 450, "NOR3_N16",
            "Yi = ~(Ai | Bi | Ci), two cells  ·  three 6N16B, the middle bulb is shared",
            ["Y1 = triodes Л101a, Л101b, Л102a;  Y2 = Л102b, Л103a, Л103b: 1.5 tubes per cell.", CHOKE, LEVELS, HEATER])
    X = [190 + 150 * i for i in range(6)]
    s.rail(RAIL, 120, 1010, "+150 V")
    BUS, CY = 170, 290
    names = [("A1", "7", "1", "6", "Л101a"), ("B1", "3", "5", "2", "Л101b"),
             ("C1", "7", "1", "6", "Л102a"), ("A2", "3", "5", "2", "Л102b"),
             ("B2", "7", "1", "6", "Л103a"), ("C2", "3", "5", "2", "Л103b")]
    for k in range(3):
        s.group(X[2 * k] - 85, CY - 70, 150 + 85 + 52, 150, f"Л10{k + 1} · 6N16B")
    P = []
    for i, (nm, g, a, kk, ref) in enumerate(names):
        p = s.triode(X[i], CY, ref, (a, g, kk))
        P.append(p)
        s.pin_in(X[i] - 80, CY, nm)
        s.wire([(X[i] - 80, CY), p["g"]])
        s.gnd(*p["k"])
    for grp, ra_x, ref, yname, pin_x, pin_anchor in (((0, 1, 2), X[1], ("R101", "L101", "R102"), "Y1", X[0] - 100, "l"),
                                                     ((3, 4, 5), X[4], ("R103", "L102", "R104"), "Y2", X[5] + 100, "r")):
        s.wire([P[grp[0]]["a"], (X[grp[0]], BUS), (X[grp[2]], BUS), P[grp[2]]["a"]], net=yname)
        s.wire([P[grp[1]]["a"], (X[grp[1]], BUS)], net=yname)
        s.dot(X[grp[1]], BUS)
        s.plate_load(ra_x, RAIL, BUS, (ref[0], "10k"), (ref[1], "680 µ"), (ref[2], "10k"))
        s.dot(ra_x, RAIL)
        if pin_anchor == "l":
            s.wire([(X[grp[0]], BUS), (pin_x, BUS)], net=yname)
            s.pin_out(pin_x, BUS, yname, left=True)
        else:
            s.wire([(X[grp[2]], BUS), (pin_x, BUS)], net=yname)
            s.pin_out(pin_x, BUS, yname)
        s.dot(X[grp[0]], BUS)
        s.dot(X[grp[2]], BUS)
    return s


def nor4_n16():
    s = Sch(900, 440, "NOR4_N16", "Y = ~(A | B | C | D)  ·  two 6N16B, four triodes on one plate",
            [CHOKE, LEVELS, HEATER])
    X = [200, 350, 530, 680]
    s.rail(RAIL, 120, 820, "+150 V")
    BUS, CY = 170, 290
    s.group(X[0] - 85, CY - 70, 150 + 85 + 52, 150, "Л101 · 6N16B")
    s.group(X[2] - 85, CY - 70, 150 + 85 + 52, 150, "Л102 · 6N16B")
    P = []
    for i, (nm, g, a, kk, ref) in enumerate([("A", "7", "1", "6", "Л101a"), ("B", "3", "5", "2", "Л101b"),
                                             ("C", "7", "1", "6", "Л102a"), ("D", "3", "5", "2", "Л102b")]):
        p = s.triode(X[i], CY, ref, (a, g, kk))
        P.append(p)
        s.pin_in(X[i] - 80, CY, nm)
        s.wire([(X[i] - 80, CY), p["g"]])
        s.gnd(*p["k"])
    s.wire([P[0]["a"], (X[0], BUS), (X[3], BUS), P[3]["a"]], net="y")
    for i in (1, 2):
        s.wire([P[i]["a"], (X[i], BUS)], net="y")
        s.dot(X[i], BUS)
    s.dot(X[0], BUS)
    s.dot(X[3], BUS)
    xr = (X[1] + X[2]) / 2
    s.plate_load(xr, RAIL, BUS, ("R101", "10k"), ("L101", "680 µ"), ("R102", "10k"))
    s.dot(xr, RAIL)
    s.wire([(X[3], BUS), (X[3] + 80, BUS)], net="y")
    s.pin_out(X[3] + 80, BUS, "Y")
    return s
