"""BUF_N16, OR2_N16, OR4_N16: 6N16B cathode followers (LV in, LV out).

The anodes sit on +150 V, the output is taken from the cathode through
R 2.2k ‖ C 100 pF (fast edge, limits the grid-current kick) and the pull-down
12k to −50 V. Followers drive only gate grids, never a divider or another
follower (BUF_N16 README)."""
from lib import Sch, LV

LEVELS = "LV in and out: 1 = +10 V, 0 = −20 V (the follower output is an LV signal, no divider needed on its load grids)."
HEATER = "Heater 6.3 V on H1/H2 (pins 8, 4), all tubes in parallel, not drawn."
RAIL = 80


def _tail(s, x, y_k, rr, rc, cr, cc, pull, y_out_x):
    """Cathode node at (x, y_k) -> RC -> Y node, pull-down to −50 V, output pin."""
    ty, by = y_k + 20, y_k + 110
    s.wire([(x, y_k), (x, ty)])
    s.rc_v(x, ty, by, rr, "2.2k", cr, "100p")
    s.wire([(x, by), (x, by + 30)])
    s.res_v(x, by, by + 90, pull, "12k")
    s.dot(x, by)
    s.vee(x, by + 90)
    s.wire([(x + 26, by), (y_out_x, by)])
    s.pin_out(y_out_x, by, "Y", color=LV)
    return by


def buf_n16():
    s = Sch(700, 590, "BUF_N16", "Y1 = A1,  Y2 = A2  ·  one 6N16B, a cathode follower per half",
            [LEVELS, HEATER])
    s.rail(RAIL, 130, 640, "+150 V")
    s.group(95, 160, 480, 170, "Л101 · 6N16B (two triodes, one bulb)")
    cy = 250
    for i, (cx, nm, pins, rr, cc, pull) in enumerate(
            [(230, "1", ("1", "7", "6"), "R101", "C101", "R102"), (470, "2", ("5", "3", "2"), "R103", "C103", "R104")]):
        t = s.triode(cx, cy, "Л101" + "ab"[i], pins)
        s.wire([(cx, RAIL), t["a"]])
        s.dot(cx, RAIL)
        s.pin_in(cx - 110, cy, "A" + nm)
        s.wire([(cx - 110, cy), t["g"]])
        cc = "C10" + str(i + 1)
        _tail(s, cx, t["k"][1], rr, 0, cc, 0, pull, cx + 90)
        s.text(cx + 8, t["k"][1] + 14, "K" + nm, 10, "#5d6670")
    return s


def or2_n16():
    s = Sch(700, 590, "OR2_N16", "Y = A | B  ·  one 6N16B, two cathodes on one load",
            ["Both triodes share one cathode load: the higher grid sets Y; the lower triode is cut off.", LEVELS, HEATER])
    s.rail(RAIL, 130, 640, "+150 V")
    s.group(95, 160, 480, 170, "Л101 · 6N16B (two triodes, one bulb)")
    cy = 250
    t1 = s.triode(230, cy, "Л101a", ("1", "7", "6"))
    t2 = s.triode(470, cy, "Л101b", ("5", "3", "2"))
    for t, cx, nm in ((t1, 230, "A"), (t2, 470, "B")):
        s.wire([(cx, RAIL), t["a"]])
        s.dot(cx, RAIL)
        s.pin_in(cx - 110, cy, nm)
        s.wire([(cx - 110, cy), t["g"]])
    ky = 335
    s.wire([t1["k"], (230, ky), (470, ky), t2["k"]], net="k")
    s.dot(350, ky)
    s.text(250, ky - 8, "K", 10, "#5d6670")
    _tail(s, 350, ky, "R101", 0, "C101", 0, "R102", 440)
    return s


def or4_n16():
    s = Sch(900, 600, "OR4_N16", "Y = A | B | C | D  ·  two 6N16B, four cathodes on one load",
            ["Four cathodes tied to one load; the highest grid sets Y.", LEVELS, HEATER])
    s.rail(RAIL, 120, 840, "+150 V")
    cy = 250
    X = [200, 350, 530, 680]
    s.group(X[0] - 85, 160, 150 + 85 + 52, 170, "Л101 · 6N16B")
    s.group(X[2] - 85, 160, 150 + 85 + 52, 170, "Л102 · 6N16B")
    T = []
    for i, (nm, pins, ref) in enumerate([("A", ("1", "7", "6"), "Л101a"), ("B", ("5", "3", "2"), "Л101b"),
                                         ("C", ("1", "7", "6"), "Л102a"), ("D", ("5", "3", "2"), "Л102b")]):
        t = s.triode(X[i], cy, ref, pins)
        T.append(t)
        s.wire([(X[i], RAIL), t["a"]])
        s.dot(X[i], RAIL)
        s.pin_in(X[i] - 80, cy, nm)
        s.wire([(X[i] - 80, cy), t["g"]])
    ky = 335
    s.wire([T[0]["k"], (X[0], ky), (X[3], ky), T[3]["k"]], net="k")
    for i in (1, 2):
        s.wire([T[i]["k"], (X[i], ky)], net="k")
        s.dot(X[i], ky)
    xm = (X[1] + X[2]) / 2
    s.dot(xm, ky)
    _tail(s, xm, ky, "R101", 0, "C101", 0, "R102", xm + 100)
    return s
