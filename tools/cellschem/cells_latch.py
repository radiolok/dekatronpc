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
        s = Sch(1370, 520, "RSLATCH_J2N16",
                "Gated RS latch: QN = ~((S·E) | Q),  Q = ~((R·E) | QN)  ·  2 × 6Zh2B + 1 × 6N16B",
                ["Each half is an AND-OR-INVERT on one plate: the pentode is the AND (S·E), the triode of Л103 is the OR "
                 "(the other plate through a divider). S = R = 1 with E = 1 is forbidden.",
                 "Plate load: Ra 10k + 1 mH choke, screens Rg2 12k (TRS v0.58, the core of every trigger, as DFFP_J2N16). Feedback dividers "
                 "(470k ‖ 3.9 pF, 200k to −50 V) inside the cell.",
                 "Л103 is one 6N16B bulb (Л103a: QN side, Л103b: Q side). The E pin is one net: it is drawn at both pentodes.",
                 LEVELS, HEATER])
        X0 = 0
    else:
        s = Sch(1510, 560, "DFFP_J2N16 (core of DFFP2_J2N16)",
                "One pulse-clocked flip-flop: the RS latch with its enable cut from the rising clock edge  ·  2 × 6Zh2B + 1 × 6N16B",
                ["The RS core of RSLATCH_J2N16 (Ra 10k + 1 mH, Rg2 12k) with the enable network changed: both g3 sit on the node G "
                 "(rest −12.4 V), which a rising clock edge lifts through Cc for ≈ 370 ns; no Cb.",
                 "G is one net: it is drawn at both pentodes. S and R come from the slow dividers of the parent sheet (150k / 62k, no speed-up capacitor).",
                 LEVELS, HEATER])
        X0 = 140
    s.rail(80, 130, 1300 + X0, "+150 V")
    CY, BUS = 290, 200 if dffp else 160
    c1, c2, c3, c4 = 230 + X0, 440 + X0, 930 + X0, 1160 + X0
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
        p1 = _pent(s, c1, CY, "Л101", "S", "E", ("C101", "15p", "−50 V"), ("R103", "12k"), "1")
        p2 = _pent(s, c4, CY, "Л102", "R", "E", ("C102", "15p", "−50 V"), ("R104", "12k"), "2", flip=True)
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
    for x, ref, lref in ((375 + X0, "R101", "L101"), (1000 + X0, "R102", "L102")):
        s.plate_load(x, 80, BUS, (ref, "10k"), (lref, "1 mH"))
        s.dot(x, 80)
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
        s.divider(x, y0, 290, f"{r1} · {c1_} · {r2}", "470k ‖ 3.9p / 200k")
        s.wire([(x, 290), gpt], net=nm)
        s.text(x + 8, 306, nm, 10.5, SUP, "start", "bold")
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


INV_SUB = "½ 6N16B · Ra 10k + 680 µH ‖ 10k"


def _inv_parts(ra, la, rd):
    """the part line of an Inverter element: its plate load references"""
    return f"{ra} + {la} ‖ {rd}"


def dlatch2():
    s = Sch(1250, 700, "DLATCH2_J2N16",
            "Two D latches with a common enable  ·  2 × RSLATCH_J2N16 + one 6N16B (inverters)",
            ["Latch k is transparent while E is high: Qk = Dk, QNk = ~Dk. R of each latch is ~D from an Inverter (half a 6N16B, "
             "Ra 10k + 680 µH ‖ 10k) through a Divider (470k ‖ 2.7 pF / 200k).",
             "Inverters, dividers and the RS latches are drawn as elements: the latch circuit is on the RSLATCH_J2N16 page. "
             "Л901a, Л901b are the two triodes of one bulb.",
             LEVELS, HEATER])
    ye = 600
    for k in range(2):
        x0 = 120 + k * 560
        n = str(k + 1)
        s.pin_in(x0 - 30, 225, "D" + n)
        inv = s.inverter(x0 + 40, 225, "Л901" + "ab"[k], _inv_parts(f"R90{2 * k + 1}", f"L90{k + 1}", f"R90{2 * k + 2}"))
        s.wire([(x0 - 30, 225), inv["in"]], net="d" + n)
        # D also goes to S
        s.wire([(x0 - 8, 225), (x0 - 8, 310), (x0 + 330, 310)], net="d" + n)
        s.dot(x0 - 8, 225)
        # DN -> Divider -> R
        dx = x0 + 200
        s.wire([inv["out"], (dx, 225), (dx, 335)], net="dn" + n)
        s.text(inv["out"][0] + 8, 217, "DN" + n, 10, SUP, "start", "bold")
        s.divider(dx, 335, 430, f"R90{2 * k + 5} · C90{k + 1} · R90{2 * k + 6}", "470k ‖ 2.7p / 200k", side="left")
        s.wire([(dx, 430), (x0 + 330, 430)], net="rn" + n)
        s.text(dx + 8, 422, "R" + n, 10, SUP, "start", "bold")
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
            ["D and C are HV pins. D reaches S through a slow Divider 150k / 62k with no speed-up capacitor (delay ≈ 150 ns): the bistable "
             "needs 100…230 ns to flip, so the new D must not race through the open gate.",
             "Each flip-flop has its own Inverter, half of Л901 (a for FF1, b for FF2), Ra 10k without a choke: it is part of the D delay "
             "(a choke costs 30 ns of hold). The core is drawn in full on the DFFP_J2N16 core figure. At most two D pins per net (1.2 mA DC each).",
             LEVELS, HEATER])
    # D input
    s.pin_in(60, 225, "D", color=HV)
    s.wire([(60, 225), (118, 225)], net="d")
    s.dot(118, 225)
    # D -> Divider (to the inverter grid) -> Inverter -> DN
    s.divider(118, 225, 250, "R903 · C901 · R904", "470k ‖ 3.9p / 200k", horizontal=True)
    inv = s.inverter(266, 225, "Л901a", "R901 10k, no choke")
    s.wire([(250, 225), inv["in"]], net="di")
    s.wire([inv["out"], (450, 225)], net="dn")
    s.text(inv["out"][0] + 8, 217, "DN", 10, SUP, "start", "bold")
    # DN -> slow Divider R111 / R112 -> R
    s.divider(450, 225, 430, "R111 · R112", "150k / 62k, no C1", side="left")
    s.wire([(450, 430), (600, 430)], net="r")
    s.text(458, 422, "R", 10.5, SUP, "start", "bold")
    # D -> slow Divider R109 / R110 -> S
    s.wire([(118, 225), (118, 590), (380, 590)], net="d")
    s.divider(380, 590, 540, "R109 · R110", "150k / 62k, no C1", horizontal=True)
    s.wire([(540, 590), (570, 590), (570, 310), (600, 310)], net="s")
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
    notes = ["Master M: S = D, R = ~D, E = C. Slave S: S = QM, R = QNM, E = ~C. Two Inverters (Л901a: D, Л901b: C; Ra 10k + 680 µH ‖ 10k each); "
             "each inverter plate reaches its latch through a Divider (470k ‖ C / 200k to −50 V).",
             "Master outputs reach the slave through their own 2.7 pF Dividers; the slave enable Divider has 13.6 pF (the clock edge is delayed against D)."]
    if variant == "rn":
        notes.append("RN is the reset line (idle −20 V, GND = reset): one diode of Л902 to FQN of each latch pulls the triode on plate Q "
                     "on, so Q goes low. Cc 2.7 pF (QN → FQN) compensates the diode capacitance.")
    elif variant == "sn":
        notes.append("SN is the reset line (idle −20 V, GND = set): one diode of Л902 to FQ of each latch pulls the triode on plate QN "
                     "on, so Q goes high. Cc 2.7 pF (Q → FQ) compensates the diode capacitance.")
    notes += ["The RS latches, Inverters and Dividers are drawn as elements: the latch circuit is on the RSLATCH_J2N16 page.",
              LEVELS, HEATER]
    h = 700 + (95 if variant != "plain" else 0) + 14 * (len(notes) - 4)
    s = Sch(1330, h, names[variant], sub, notes)
    S_, R_, E_ = 310, 430, 550
    # D -> Inverter (Л901a) -> DN; D -> S
    s.pin_in(90, 225, "D")
    ia = s.inverter(170, 225, "Л901a", _inv_parts("R901", "L901", "R902"))
    s.wire([(90, 225), ia["in"]], net="d")
    s.dot(130, 225)
    s.wire([(130, 225), (130, S_), (600, S_)], net="d")
    # DN -> Divider -> R
    s.wire([ia["out"], (480, 225), (480, 335)], net="dn")
    s.text(ia["out"][0] + 8, 217, "DN", 10, SUP, "start", "bold")
    s.divider(480, 335, R_, "R905 · C901 · R906", "470k ‖ 2.7p / 200k", side="left")
    s.wire([(480, R_), (600, R_)], net="rm")
    s.text(488, R_ - 8, "RM", 10, SUP, "start", "bold")
    # C -> E and C -> Inverter (Л901b) -> CN
    s.pin_in(90, E_, "C")
    s.wire([(90, E_), (600, E_)], net="c")
    s.dot(270, E_)
    ib = s.inverter(330, 120, "Л901b", _inv_parts("R903", "L902", "R904"))
    s.wire([(270, E_), (270, 120), ib["in"]], net="c")
    fq = {"rn": {"FQN": 490}, "sn": {"FQ": 370}}.get(variant, {})
    M = rs_block(s, 600, 260, 140, 340, "master M", {"S": S_, "R": R_, "E": E_}, {"Q": 310, "QN": 430, **fq})
    Sl = rs_block(s, 1000, 260, 140, 340, "slave S", {"S": S_, "R": R_, "E": E_}, {"Q": 310, "QN": 430, **fq})
    # CN -> Divider -> ES -> slave E
    s.wire([ib["out"], (820, 120), (820, E_), (830, E_)], net="cn")
    s.text(ib["out"][0] + 8, 112, "CN", 10, SUP, "start", "bold")
    s.divider(830, E_, 975, "R907 · C902 · R908", "470k ‖ 13.6p / 200k", horizontal=True)
    s.wire([(975, E_), (1000, E_)], net="es")
    s.text(978, E_ - 8, "ES", 10.5, SUP, "start", "bold")
    # master -> slave Dividers
    for lane, refs, nm in ((310, "R909 · C903 · R910", "SS"), (430, "R911 · C904 · R912", "RS")):
        s.wire([(740, lane), (830, lane)], net="m" + nm)
        s.divider(830, lane, 975, refs, "470k ‖ 2.7p / 200k", horizontal=True)
        s.wire([(975, lane), (1000, lane)], net="s" + nm)
        s.text(978, lane - 8, nm, 10.5, SUP, "start", "bold")
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
