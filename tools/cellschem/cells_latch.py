"""RSLATCH_J2N16 in full; the D-latch / flip-flop family around RS-latch blocks."""
from lib import Sch, LV, HV, SUP, INK, RST
from cells_aoi import _pent

LEVELS = "LV (grids): 1 = +10 V, 0 = −20 V.   HV (plates): 1 = +150 V, 0 = +50 V."
HEATER = "Heater 6.3 V on H1/H2 of every tube, all in parallel, not drawn."


def rslatch():
    return _rs_circuit(False)


def dffp_core():
    return _rs_circuit(True)


def _rs_circuit(dffp):
    if not dffp:
        s = Sch(1260, 520, "RSLATCH_J2N16",
                "Gated RS latch: QN = ~((S·E) | Q),  Q = ~((R·E) | QN)  ·  2 × 6Zh2B + 1 × 6N16B",
                ["Each half is an AND-OR-INVERT on one plate: the pentode is the AND (S·E), the triode of Л103 is the OR "
                 "(the other plate through a divider). S = R = 1 with E = 1 is forbidden.",
                 "Feedback divider: 470k ‖ 3.9 pF in series, 200k to −50 V, inside the cell. Л103 is one 6N16B bulb "
                 "(Л103a: QN side, Л103b: Q side). The E pin is one net: it is drawn at both pentodes.",
                 LEVELS, HEATER])
        X0 = 0
    else:
        s = Sch(1400, 560, "DFFP_J2N16 (core of DFFP2_J2N16)",
                "One pulse-clocked flip-flop: the RS latch with its enable cut from the rising clock edge  ·  2 × 6Zh2B + 1 × 6N16B",
                ["As RSLATCH_J2N16 with three changes: both g3 sit on the node G (rest −12.4 V), which a rising clock edge lifts through Cc "
                 "for ≈ 370 ns; 1 mH chokes in the plate loads; Rg2 12k, no Cb.",
                 "G is one net: it is drawn at both pentodes. S and R come from the slow dividers of the parent sheet (150k / 62k, no speed-up capacitor).",
                 LEVELS, HEATER])
        X0 = 140
    s.rail(80, 130, 1190 + X0, "+150 V")
    CY, BUS = 290, 200 if dffp else 160
    c1, c2, c3, c4 = 230 + X0, 440 + X0, 820 + X0, 1050 + X0
    cb = None if dffp else ("C101", "15p", "−50 V")
    rg = ("R103", "12k") if dffp else ("R103", "15k")
    if dffp:
        p1 = s.pentode(c1, CY, "Л101")
        p2 = s.pentode(c4, CY, "Л102", flip=True)
        for p, flip, nm, rgn, sx_sign in ((p1, False, "S", "R103", 1), (p2, True, "R", "R104", -1)):
            m = -1 if flip else 1
            px = p["g1"][0] - 58 * m
            s.pin_in(px, p["g1"][1], nm, right=flip)
            s.wire([(px, p["g1"][1]), p["g1"]])
            sx = p["g2"][0] + 30 * m
            s.wire([p["g2"], (sx, p["g2"][1])])
            s.res_v(sx, p["g2"][1] - 92, p["g2"][1], rgn, "12k")
            s.vcc(sx, p["g2"][1] - 92, "+150 V")
            s.gnd(*p["k"])
        # G network on the left pentode, tag on the right one
        g3 = p1["g3"]
        gx = g3[0] - 24
        s.wire([g3, (gx - 110, g3[1])], net="g")
        for xx, kind in ((gx - 110, "c"), (gx - 55, "r113"), (gx, "r114")):
            s.dot(xx, g3[1])
        s.pin_in(gx - 110, g3[1] - 80, "C", color=HV)
        s.wire([(gx - 110, g3[1] - 80), (gx - 110, g3[1] - 66)], net="cwire")
        s.cap_v(gx - 110, g3[1] - 66, g3[1], "C103", "3.9p", side="left")
        s.res_v(gx - 55, g3[1] - 46, g3[1], "R113", "43k", side="left")
        s.vcc(gx - 55, g3[1] - 46, "GND")
        s.res_v(gx, g3[1] - 46, g3[1], "R114", "130k", side="right")
        s.vcc(gx, g3[1] - 46, "−50 V")
        s.text(gx - 100, g3[1] - 100, "", 1)
        g3b = p2["g3"]
        tx = g3b[0] + 58
        s.pin_in(tx, g3b[1], "G", right=True, color=SUP)
        s.wire([g3b, (tx, g3b[1])])
        s.text(gx - 100, g3[1] + 14, "G", 10.5, SUP, "start", "bold")
    else:
        p1 = _pent(s, c1, CY, "Л101", "S", "E", ("C101", "15p", "−50 V"), ("R103",), "1")
        p2 = _pent(s, c4, CY, "Л102", "R", "E", ("C102", "15p", "−50 V"), ("R104",), "2", flip=True)
    t1 = s.triode(c2, CY, "Л103a", ("1", "7", "6"), flip=True)
    t2 = s.triode(c3, CY, "Л103b", ("5", "3", "2"))
    s.gnd(*t1["k"])
    s.gnd(*t2["k"])
    # QN plate: Л101 + Л103a; Q plate: Л103b + Л102
    s.wire([(150 + X0, BUS), (c2 + 40, BUS)], net="qn")
    s.wire([p1["a"], (c1, BUS)], net="qn")
    s.wire([t1["a"], (c2, BUS)], net="qn")
    s.dot(c1, BUS)
    s.dot(c2, BUS)
    s.pin_out(150 + X0, BUS, "QN", left=True)
    s.wire([(c3 - 40, BUS), (c4 + 100, BUS)], net="q")
    s.wire([t2["a"], (c3, BUS)], net="q")
    s.wire([p2["a"], (c4, BUS)], net="q")
    s.dot(c3, BUS)
    s.dot(c4, BUS)
    s.pin_out(c4 + 100, BUS, "Q")
    for x, ref, lref in ((375 + X0, "R101", "L101"), (890 + X0, "R102", "L102")):
        if dffp:
            s.res_v(x, 80, 126, ref, "10k")
            s.ind_v(x, 126, BUS, lref, "1 mH")
        else:
            s.res_v(x, 80, BUS, ref, "10k")
        s.dot(x, 80)
        s.dot(x, BUS)
    # feedback: Q -> FQ (grid of Л103a), QN -> FQN (grid of Л103b)
    xq, xn = c2 + 105, c2 + 275
    top = BUS - 60 if dffp else BUS - 42
    s.wire([(c3 - 40, BUS), (c3 - 40, top + 14), (xq, top + 14), (xq, top + 36)], net="fq")
    s.dot(c3 - 40, BUS)
    s.wire([(c2 + 40, BUS), (c2 + 40, top), (xn, top), (xn, top + 36)], net="fqn")
    s.dot(c2 + 40, BUS)
    y0 = top + 36
    for x, r1, c1_, r2, nm, gpt in ((xq, "R105", "C101" if dffp else "C103", "R106", "FQ", t1["g"]),
                                    (xn, "R107", "C102" if dffp else "C104", "R108", "FQN", t2["g"])):
        s.rc_v(x, y0, y0 + 80, r1, "470k", c1_, "3.9p")
        s.wire([(x, y0 + 80), (x, 290)], net=nm)
        s.dot(x, 290)
        s.wire([(x, 290), gpt], net=nm)
        s.res_v(x, 290, 380, r2, "200k")
        s.vee(x, 380)
        s.text(x + 8, 280, nm, 10.5, SUP, "start", "bold")
    return s


# ---------------------------------------------------------------- blocks
def rs_block(s, x, y, w, h, ref, left, right, bottom=(), title="RSLATCH_J2N16"):
    """RSLATCH_J2N16 drawn as a block. left/right: {pin: y}, bottom: {pin: x}. Returns outer pin points."""
    s.box(x, y, w, h, title, ref)
    pts = {}
    for nm, yy in left.items():
        s.body.append(f'<circle cx="{x:g}" cy="{yy:g}" r="3.4" fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        s.text(x + 9, yy + 4, nm, 11.5, INK, "start", "bold")
        pts[nm] = (x, yy)
    for nm, yy in right.items():
        s.body.append(f'<circle cx="{x + w:g}" cy="{yy:g}" r="3.4" fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        s.text(x + w - 9, yy + 4, nm, 11.5, INK, "end", "bold")
        pts[nm] = (x + w, yy)
    for nm, xx in dict(bottom).items():
        s.body.append(f'<circle cx="{xx:g}" cy="{y + h:g}" r="3.4" fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        s.text(xx, y + h - 9, nm, 11.5, INK, "middle", "bold")
        pts[nm] = (xx, y + h)
    return pts


def _inverter(s, cx, cy, node_y, ref, pins, ra_ref, in_name, in_pin_x, rail_y):
    """6N16B inverter triode: grid pin on the left, plate node (cx, node_y) with Ra 10k from the rail."""
    t = s.triode(cx, cy, ref, pins)
    s.res_v(cx, rail_y, node_y, ra_ref, "10k")
    s.dot(cx, rail_y)
    s.wire([(cx, node_y), t["a"]], net=("pl", ref))
    s.dot(cx, node_y)
    s.gnd(*t["k"])
    s.pin_in(in_pin_x, cy, in_name)
    s.wire([(in_pin_x, cy), t["g"]], net=("in", ref))
    return t


def dlatch2():
    s = Sch(1250, 700, "DLATCH2_J2N16",
            "Two D latches with a common enable  ·  2 × RSLATCH_J2N16 + one 6N16B (inverters)",
            ["Latch k is transparent while E is high: Qk = Dk, QNk = ~Dk. R of each latch is ~D from a 6N16B inverter through a "
             "2.7 pF divider (470k ‖ 2.7 pF / 200k).",
             "The RS latches are drawn as blocks: their circuit is on the RSLATCH_J2N16 page. Л901a, Л901b are the two triodes of one bulb.",
             LEVELS, HEATER])
    s.rail(64, 70, 1190, "+150 V")
    ye = 600
    for k in range(2):
        x0 = 120 + k * 560
        n = str(k + 1)
        t = _inverter(s, x0 + 100, 225, 130, "Л901" + "ab"[k], ("1", "7", "6") if k == 0 else ("5", "3", "2"),
                      "R90" + str(k + 1), "D" + n, x0 - 30, 64)
        # D also goes to S
        s.wire([(x0 - 8, 225), (x0 - 8, 310), (x0 + 330, 310)], net="d" + n)
        s.dot(x0 - 8, 225)
        # DN -> divider -> R
        dx = x0 + 230
        s.wire([(x0 + 100, 130), (dx, 130), (dx, 180)], net="dn" + n)
        s.rc_v(dx, 180, 260, "R" + str(903 + 2 * k), "470k", "C90" + str(k + 1), "2.7p")
        s.wire([(dx, 260), (dx, 430)], net="rn" + n)
        s.dot(dx, 430)
        s.res_v(dx, 430, 480, "R" + str(904 + 2 * k), "200k")
        s.vee(dx, 480)
        s.wire([(dx, 430), (x0 + 330, 430)], net="rn" + n)
        s.text(dx + 8, 422, "R" + n, 10, SUP, "start", "bold")
        s.text(dx + 8, 302, "", 1)
        b = rs_block(s, x0 + 330, 260, 130, 290, "Latch " + n, {"S": 310, "R": 430}, {"Q": 310, "QN": 430},
                     {"E": x0 + 395})
        s.wire([b["Q"], (x0 + 520, 310)], net="q" + n)
        s.pin_out(x0 + 520, 310, "Q" + n)
        s.wire([b["QN"], (x0 + 520, 430)], net="qn" + n)
        s.pin_out(x0 + 520, 430, "QN" + n)
        s.wire([b["E"], (b["E"][0], ye)], net="e")
        s.dot(b["E"][0], ye)
    s.pin_in(80, ye, "E")
    s.wire([(80, ye), (120 + 395 + 560, ye)], net="e")
    return s


def dffp2():
    s = Sch(1230, 770, "DFFP2_J2N16",
            "Two pulse-clocked D flip-flops, rising edge of C  ·  one flip-flop shown, the sheet holds two (2 × 3.5 tubes)",
            ["D and C are HV pins. D reaches S through 150k / 62k with no speed-up capacitor (delay ≈ 150 ns): the bistable needs 100…230 ns "
             "to flip, so the new D must not race through the open gate.",
             "Each flip-flop has its own half of the D inverter Л901 (a for FF1, b for FF2). The core is drawn in full on the "
             "DFFP_J2N16 core figure. At most two D pins of this cell on one net (1.2 mA DC each).",
             LEVELS, HEATER])
    s.rail(64, 70, 1160, "+150 V")
    # D input
    s.pin_in(60, 225, "D", color=HV)
    s.wire([(60, 225), (118, 225)], net="d")
    s.dot(118, 225)
    # inverter grid network: C901 || R903 (HV -> LV), R904 to -50 V
    s.wire([(118, 225), (150, 225)], net="d")
    s.rc_h(150, 270, 225, "R903", "470k", "C901", "3.9p")
    s.wire([(270, 225), (330, 225)], net="di")
    s.dot(300, 225)
    s.res_v(300, 225, 285, "R904", "200k")
    s.vee(300, 285)
    t = s.triode(392, 225, "Л901a", ("1", "7", "6"))
    s.wire([(330, 225), t["g"]], net="di")
    s.res_v(392, 64, 130, "R901", "10k")
    s.dot(392, 64)
    s.wire([(392, 130), t["a"]], net="dn")
    s.dot(392, 130)
    s.gnd(*t["k"])
    # DN -> R111/R112 -> R
    s.wire([(392, 130), (450, 130), (450, 190)], net="dn")
    s.res_v(450, 190, 270, "R111", "150k")
    s.wire([(450, 270), (450, 430)], net="r")
    s.dot(450, 430)
    s.res_v(450, 430, 500, "R112", "62k")
    s.vee(450, 500)
    s.wire([(450, 430), (600, 430)], net="r")
    s.text(458, 422, "R", 10.5, SUP, "start", "bold")
    # D -> R109/R110 -> S
    s.dot(118, 225)
    s.wire([(118, 225), (118, 590), (410, 590)], net="d")
    s.res_h(410, 540, 590, "R109", "150k", side="above")
    s.wire([(540, 590), (570, 590), (570, 310), (600, 310)], net="s")
    s.dot(570, 310)
    s.res_v(570, 238, 310, "R110", "62k", side="left")
    s.vcc(570, 238, "−50 V")
    s.text(578, 328, "S", 10.5, SUP, "start", "bold")
    # core block, clock
    b = rs_block(s, 600, 260, 150, 340, "pulse-clocked flip-flop", {"S": 310, "R": 430}, {"Q": 310, "QN": 430},
                 {"G": 675}, title="DFFP_J2N16 core")
    s.pin_in(675, 660, "C", color=HV)
    s.wire([(675, 660), (675, 600)], net="c")
    s.wire([(b["Q"][0], 310), (850, 310)], net="q")
    s.pin_out(850, 310, "Q")
    s.wire([(b["QN"][0], 430), (850, 430)], net="qn")
    s.pin_out(850, 430, "QN")
    s.text(692, 640, "inside: Cc 3.9 pF from C to G, 43k to GND, 130k to −50 V", 10.5, SUP)
    return s


def dff(variant="plain"):
    names = {"plain": "DFF_J2N16", "rn": "DFFRN_J2N16X7", "sn": "DFFSN_J2N16X7"}
    sub = {"plain": "D flip-flop, falling edge of C: master latch + slave latch + inverters  ·  2 × RSLATCH_J2N16 + one 6N16B",
           "rn": "D flip-flop with asynchronous clear (RN = 0)  ·  DFF_J2N16 + one 6Kh7B double diode",
           "sn": "D flip-flop with asynchronous preset (SN = 0)  ·  DFF_J2N16 + one 6Kh7B double diode"}[variant]
    notes = ["Master M: S = D, R = ~D, E = C. Slave S: S = QM, R = QNM, E = ~C. Л901a inverts D, Л901b inverts C; "
             "each inverter plate reaches its latch through a divider (470k ‖ C / 200k).",
             "Master outputs reach the slave through their own 2.7 pF dividers; the slave enable divider has 13.6 pF (the clock edge is delayed against D)."]
    if variant == "rn":
        notes.append("RN is the reset line (idle −20 V, GND = reset): one diode of Л902 to FQN of each latch pulls the triode on plate Q "
                     "on, so Q goes low. Cc 2.7 pF (QN → FQN) compensates the diode capacitance.")
    elif variant == "sn":
        notes.append("SN is the reset line (idle −20 V, GND = set): one diode of Л902 to FQ of each latch pulls the triode on plate QN "
                     "on, so Q goes high. Cc 2.7 pF (Q → FQ) compensates the diode capacitance.")
    notes += ["The RS latches are drawn as blocks: their circuit is on the RSLATCH_J2N16 page.", LEVELS, HEATER]
    h = 700 + (95 if variant != "plain" else 0) + 14 * (len(notes) - 4)
    s = Sch(1330, h, names[variant], sub, notes)
    s.rail(64, 70, 1300, "+150 V")
    S_, R_, E_ = 310, 430, 550
    # inverter bulb
    ta = _inverter(s, 200, 225, 140, "Л901a", ("1", "7", "6"), "R901", "D", 90, 64)
    tb = s.triode(360, 225, "Л901b", ("5", "3", "2"))
    s.res_v(360, 64, 110, "R902", "10k")
    s.dot(360, 64)
    s.wire([(360, 110), tb["a"]], net="cn")
    s.dot(360, 110)
    s.gnd(*tb["k"])
    # D -> S
    s.dot(130, 225)
    s.wire([(130, 225), (130, S_), (600, S_)], net="d")
    # DN -> divider -> R
    s.wire([(200, 140), (480, 140), (480, 180)], net="dn")
    s.rc_v(480, 180, 260, "R903", "470k", "C901", "2.7p")
    s.wire([(480, 260), (480, R_)], net="rm")
    s.dot(480, R_)
    s.res_v(480, R_, R_ + 50, "R904", "200k")
    s.vee(480, R_ + 50)
    s.wire([(480, R_), (600, R_)], net="rm")
    # C -> E and C -> Л901b grid
    s.pin_in(90, E_, "C")
    s.wire([(90, E_), (600, E_)], net="c")
    s.dot(270, E_)
    s.wire([(270, E_), (270, 225), (tb["g"][0], 225)], net="c")
    fq = {"rn": {"FQN": 490}, "sn": {"FQ": 370}}.get(variant, {})
    M = rs_block(s, 600, 260, 140, 340, "master M", {"S": S_, "R": R_, "E": E_}, {"Q": 310, "QN": 430, **fq})
    Sl = rs_block(s, 1000, 260, 140, 340, "slave S", {"S": S_, "R": R_, "E": E_}, {"Q": 310, "QN": 430, **fq})
    # CN -> ES -> slave E
    s.wire([(360, 110), (820, 110), (820, E_)], net="cn")
    s.rc_h(820, 930, E_, "R905", "470k", "C902", "13.6p")
    s.res_v(930, E_, E_ + 50, "R906", "200k")
    s.vee(930, E_ + 50)
    s.wire([(930, E_), (1000, E_)], net="es")
    s.text(942, E_ - 8, "ES", 10.5, SUP, "start", "bold")
    # master -> slave dividers
    for lane, rr, cc, r2, nm, up in ((310, "R907", "C903", "R908", "SS", True), (430, "R909", "C904", "R910", "RS", False)):
        s.wire([(740, lane), (850, lane)], net="m" + nm)
        s.rc_h(850, 950, lane, rr, "470k", cc, "2.7p")
        s.wire([(950, lane), (1000, lane)], net="s" + nm)
        if up:
            s.res_v(950, lane - 50, lane, r2, "200k")
            s.vcc(950, lane - 50, "−50 V")
        else:
            s.res_v(950, lane, lane + 50, r2, "200k")
            s.vee(950, lane + 50)
        s.text(962, lane + (16 if up else -6), nm, 10.5, SUP, "start", "bold")
    s.text(748, 303, "QM", 10, SUP, "start", "bold")
    s.text(748, 423, "QNM", 10, SUP, "start", "bold")
    # outputs
    s.wire([Sl["Q"], (1230, 310)], net="q")
    s.pin_out(1230, 310, "Q")
    s.wire([Sl["QN"], (1230, 430)], net="qn")
    s.pin_out(1230, 430, "QN")
    # asynchronous line
    if variant != "plain":
        yr = 690
        fqn = variant == "rn"
        pn = "RN" if fqn else "SN"
        s.pin_in(90, yr, pn, sub="reset line", color=RST)
        s.wire([(90, yr), (1170, yr)], net="rst", color=RST)
        # (block, x of the Cc/diode column)
        for blk, xc in ((M, 770), (Sl, 1170)):
            y_out = 430 if fqn else 310
            y_fq = 490 if fqn else 370
            s.wire([(blk["FQN" if fqn else "FQ"][0], y_fq), (xc, y_fq)], net=("fq", xc))
            s.dot(xc, y_fq)
            s.cap_v(xc, y_out, y_fq, "Cc", "2.7p", side="right")
            s.wire([(blk["QN" if fqn else "Q"][0], y_out), (xc, y_out)], net=("o", xc))
            s.dot(xc, y_out)
            s.diode(xc, y_fq, yr - 0, "Л902" + ("a" if blk is M else "b"), None, up=True)
            s.dot(xc, yr, RST)
    return s
