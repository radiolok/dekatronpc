"""Drawing primitives for the overview schematics of the tube logic cells.

The KiCad sheets in sch/logic/<CELL>/ are wired with net labels, so the
whole circuit is hard to see at a glance. These figures redraw the same
netlist as one picture: tubes, plate loads, screens, feedback dividers,
with the supply rails and ground as symbols.

Plain Python, no dependencies. Every figure is a standalone SVG with its
own white background, so it reads the same in light and dark README
viewers. Colours: wires dark, LV signal pins blue, HV signal pins red,
supply grey (REQ-MOD-012 levels).
"""
import html

INK = "#22262b"      # wires and symbols
LV = "#1c5fb0"       # LV (grid) pins
HV = "#b8232f"       # HV (plate) pins
SUP = "#5d6670"      # supplies, rails, notes
RST = "#7a3fb5"      # reset line pins (RN, SN)
PAD = "#8b929a"      # pin numbers
ENV = "#f4f1e6"      # tube envelope fill
FONT = "DejaVu Sans, Arial, sans-serif"


def esc(s):
    return html.escape(str(s), quote=False)


class Sch:
    def __init__(self, w, h, title, sub=None, notes=()):
        self.w, self.h = w, h
        self.title, self.sub, self.notes = title, sub, list(notes)
        self.under = []      # envelopes and groups (drawn first)
        self.body = []       # symbols and text
        self.wires = []      # (points, net, colour)
        self.leads = []      # vertical component leads: hops go over them too
        self.dots = []

    # ------------------------------------------------------------ basics
    def text(self, x, y, t, size=11, fill=INK, anchor="start", weight="normal",
             style="normal"):
        self.body.append(
            f'<text x="{x:g}" y="{y:g}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-weight="{weight}" font-style="{style}">'
            f'{esc(t)}</text>')

    def line(self, x1, y1, x2, y2, stroke=INK, sw=1.6, dash=None, cap="round"):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.body.append(
            f'<line x1="{x1:g}" y1="{y1:g}" x2="{x2:g}" y2="{y2:g}" stroke="{stroke}" '
            f'stroke-width="{sw}" stroke-linecap="{cap}"{d}/>')

    def path(self, d, stroke=INK, sw=1.6, fill="none"):
        self.body.append(
            f'<path d="{d}" stroke="{stroke}" stroke-width="{sw}" fill="{fill}" '
            f'stroke-linejoin="round" stroke-linecap="round"/>')

    def wire(self, pts, net=None, color=INK, sw=1.6):
        self.wires.append((list(pts), net if net is not None else object(), color, sw))

    def dot(self, x, y, color=INK):
        self.dots.append((x, y, color))

    def group(self, x, y, w, h, label, label_dx=8):
        """Dashed envelope: several triodes in one bulb, or a sub-circuit."""
        self.under.append(
            f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="14" '
            f'fill="none" stroke="{SUP}" stroke-width="1.1" stroke-dasharray="6 4"/>')
        self.under.append(
            f'<text x="{x + label_dx:g}" y="{y + h - 8:g}" font-size="11" fill="{SUP}" '
            f'font-style="italic">{esc(label)}</text>')

    # ------------------------------------------------------------- tubes
    def _cathode(self, cx, y, m=1):
        # inverted-U cathode with its lead
        self.path(f"M{cx - 10:g},{y + 6:g} Q{cx:g},{y - 8:g} {cx + 10:g},{y + 6:g}", sw=2.2)

    def triode(self, cx, cy, ref, pins=("1", "7", "6"), flip=False, bulb=True,
               tube=None, label_side="right"):
        """One triode. Returns pin points a (top), g (side), k (bottom)."""
        m = -1 if flip else 1
        r = 31
        if bulb:
            self.body.append(
                f'<circle cx="{cx:g}" cy="{cy:g}" r="{r}" fill="{ENV}" stroke="{INK}" stroke-width="1.5"/>')
        pa, pg, pk = pins
        # anode
        self.line(cx - 12, cy - 15, cx + 12, cy - 15, sw=2.4)
        self.line(cx, cy - 15, cx, cy - 50)
        # grid: dashed bar and lead
        self.line(cx - 14, cy, cx + 14, cy, sw=1.6, dash="5 4", cap="butt")
        self.line(cx - 14 * m, cy, cx - 62 * m, cy)
        # cathode
        self._cathode(cx, cy + 11)
        self.line(cx, cy + 16, cx, cy + 50)
        # pin numbers
        self.text(cx + 5, cy - 40, pa, 9, PAD)
        self.text(cx - 60 * m + (0 if not flip else -8), cy - 5, pg, 9, PAD,
                  anchor="start" if not flip else "start")
        self.text(cx + 5, cy + 44, pk, 9, PAD)
        # reference
        if ref:
            self.text(cx - 8, cy - 36, ref, 10.5, SUP, anchor="end")
        return {"a": (cx, cy - 50), "g": (cx - 62 * m, cy), "k": (cx, cy + 50)}

    def pentode(self, cx, cy, ref, flip=False, label_side="right"):
        """6Zh2B: g1 (pin 7) and g3 (pin 2) are both signal inputs, g2 (pin 3) is the screen.

        Returns a, k, g1, g3 (left side) and g2 (right side)."""
        m = -1 if flip else 1
        r = 39
        self.body.append(
            f'<circle cx="{cx:g}" cy="{cy:g}" r="{r}" fill="{ENV}" stroke="{INK}" stroke-width="1.5"/>')
        self.line(cx - 13, cy - 22, cx + 13, cy - 22, sw=2.4)
        self.line(cx, cy - 22, cx, cy - 56)
        # g3 (upper left), g2 (screen, right), g1 (lower left)
        for yy in (-10, 2, 14):
            self.line(cx - 15, cy + yy, cx + 15, cy + yy, sw=1.5, dash="5 4", cap="butt")
        self.line(cx - 15 * m, cy - 10, cx - 68 * m, cy - 10)
        self.line(cx + 15 * m, cy + 2, cx + 68 * m, cy + 2)
        self.line(cx - 15 * m, cy + 14, cx - 68 * m, cy + 14)
        self._cathode(cx, cy + 24)
        self.line(cx, cy + 29, cx, cy + 56)
        gx = cx - 68 * m
        off = -4 if not flip else 4
        anc = "end" if not flip else "start"
        self.text(cx + 5, cy - 46, "1", 9, PAD)
        self.text(gx + (5 if not flip else -5), cy - 13, "g3·2", 9, PAD,
                  anchor="start" if not flip else "end")
        self.text(gx + (5 if not flip else -5), cy + 24, "g1·7", 9, PAD,
                  anchor="start" if not flip else "end")
        self.text(cx + 68 * m + (-4 if not flip else 4), cy - 3, "g2·3", 9, PAD,
                  anchor="end" if not flip else "start")
        self.text(cx + 5, cy + 50, "6", 9, PAD)
        if ref:
            self.text(cx - 8, cy - 42, ref, 10.5, SUP, anchor="end")
        return {"a": (cx, cy - 56), "k": (cx, cy + 56), "g1": (gx, cy + 14),
                "g3": (gx, cy - 10), "g2": (cx + 68 * m, cy + 2)}

    # --------------------------------------------------------- passives
    def res_v(self, x, y1, y2, ref, val, side="right"):
        """Vertical resistor between y1 and y2 (leads included)."""
        h, w = 30, 11
        cy = (y1 + y2) / 2
        self.line(x, y1, x, cy - h / 2)
        self.line(x, cy + h / 2, x, y2)
        self.leads.append((x, y1, cy - h / 2))
        self.leads.append((x, cy + h / 2, y2))
        self.body.append(
            f'<rect x="{x - w / 2:g}" y="{cy - h / 2:g}" width="{w}" height="{h}" '
            f'fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        self._plabel(x, cy, ref, val, side, w / 2 + 6)

    def res_h(self, x1, x2, y, ref, val, side="above"):
        w, h = 30, 11
        cx = (x1 + x2) / 2
        self.line(x1, y, cx - w / 2, y)
        self.line(cx + w / 2, y, x2, y)
        self.body.append(
            f'<rect x="{cx - w / 2:g}" y="{y - h / 2:g}" width="{w}" height="{h}" '
            f'fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        if side == "above":
            self.text(cx, y - 11, val, 11, INK, "middle", "bold")
            self.text(cx, y - 22, ref, 9, SUP, "middle")
        else:
            self.text(cx, y + 20, val, 11, INK, "middle", "bold")
            self.text(cx, y + 31, ref, 9, SUP, "middle")

    def cap_v(self, x, y1, y2, ref, val, side="right"):
        cy = (y1 + y2) / 2
        self.line(x, y1, x, cy - 4)
        self.line(x, cy + 4, x, y2)
        self.leads.append((x, y1, cy - 4))
        self.leads.append((x, cy + 4, y2))
        self.line(x - 11, cy - 4, x + 11, cy - 4, sw=2.2)
        self.line(x - 11, cy + 4, x + 11, cy + 4, sw=2.2)
        self._plabel(x, cy, ref, val, side, 15)

    def ind_v(self, x, y1, y2, ref, val, side="right"):
        cy = (y1 + y2) / 2
        top, bot = cy - 16, cy + 16
        self.line(x, y1, x, top)
        self.line(x, bot, x, y2)
        d = f"M{x:g},{top:g}"
        n = 4
        step = (bot - top) / n
        for i in range(n):
            d += f" a{step / 2 + 1:g},{step / 2:g} 0 0 1 0,{step:g}"
        self.path(d, sw=1.6)
        self._plabel(x, cy, ref, val, side, 14)

    def rc_v(self, x, y1, y2, rref, rval, cref, cval, dx=26):
        """R in parallel with C, vertical; the series lead enters at (x, y1) and leaves at (x, y2)."""
        xr, xc = x - dx, x + dx
        self.wire([(xr, y1), (xc, y1)], net=("rc", x, y1))
        self.wire([(xr, y2), (xc, y2)], net=("rc", x, y2))
        self.res_v(xr, y1, y2, rref, rval, side="left")
        self.cap_v(xc, y1, y2, cref, cval, side="right")
        self.dot(x, y1)
        self.dot(x, y2)

    def plate_load(self, x, y1, y2, ra, la, rd=None, rd_side="right", dx=34):
        """Plate load (TRS v0.58): Ra from (x, y1), then the choke L, with its damping resistor Rd in parallel
        dx to one side, down to the plate node (x, y2). ra, la, rd = (ref, value); rd None: a bare choke.
        Needs y2 - y1 >= 80. Ra and L are labelled on the side away from Rd."""
        lab = "left" if rd and rd_side == "right" else "right"
        ym = y1 + 38
        self.res_v(x, y1, ym, ra[0], ra[1], side=lab)
        self.ind_v(x, ym, y2, la[0], la[1], side=lab)
        if rd:
            sx = x + dx if rd_side == "right" else x - dx
            self.wire([(x, ym), (sx, ym)], net=("rd", x, ym))
            self.res_v(sx, ym, y2, rd[0], rd[1], side=rd_side)
            self.wire([(sx, y2), (x, y2)], net=("rd", x, y2))
            self.dot(x, ym)
        self.dot(x, y2)

    def inverter(self, x, y, ref, sub=None, w=58):
        """The element "Inverter" (half a 6N16B with its plate load): input (x, y) on the left, output (x + w, y).
        ref, sub: the reference and the part line under the symbol."""
        h = 40
        tx = x + w - 12
        self.line(x, y, x + 10, y)
        self.path(f"M{x + 10:g},{y - h / 2:g} L{tx - 9:g},{y:g} L{x + 10:g},{y + h / 2:g} Z", sw=1.6, fill="#f3f6fb")
        self.body.append(f'<circle cx="{tx - 4:g}" cy="{y:g}" r="4.5" fill="#fff" stroke="{INK}" stroke-width="1.5"/>')
        self.line(tx + 0.5, y, x + w, y)
        self.text(x + w / 2 - 6, y - h / 2 - 6, "Inverter", 10.5, INK, "middle", "bold")
        self.text(x + w / 2 - 6, y + h / 2 + 13, ref, 9.5, SUP, "middle")
        if sub:
            self.text(x + w / 2 - 6, y + h / 2 + 25, sub, 8.5, SUP, "middle")
        return {"in": (x, y), "out": (x + w, y)}

    def divider(self, x, y1, y2, refs, vals, side="right", horizontal=False):
        """The element "Divider": HV in, LV out (R1 || C1 in series, R2 to -50 V inside). Vertical from (x, y1) (HV)
        to (x, y2) (LV); horizontal from (x, y1) to (y2, y1) when horizontal (y2 is then the right end x).
        refs, vals: one line each, e.g. "R905 · C901 · R906", "470k ‖ 2.7p / 200k"."""
        bw, bh = (78, 34) if horizontal else (34, 46)
        if horizontal:
            x1, x2, y = x, y2, y1
            cx = (x1 + x2) / 2
            self.line(x1, y, cx - bw / 2, y)
            self.line(cx + bw / 2, y, x2, y)
            bx, by = cx - bw / 2, y - bh / 2
        else:
            cy = (y1 + y2) / 2
            self.line(x, y1, x, cy - bh / 2)
            self.line(x, cy + bh / 2, x, y2)
            self.leads.append((x, y1, cy - bh / 2))
            self.leads.append((x, cy + bh / 2, y2))
            bx, by = x - bw / 2, cy - bh / 2
        self.body.append(f'<rect x="{bx:g}" y="{by:g}" width="{bw}" height="{bh}" rx="4" fill="#fff8ec" '
                         f'stroke="{INK}" stroke-width="1.5"/>')
        if horizontal:
            self.text(bx + bw / 2, by + 14, "Divider", 10, INK, "middle", "bold")
            self.text(bx + bw / 2, by + 27, "HV → LV", 8.5, SUP, "middle")
            self.text(bx + bw / 2, by + bh + 13, vals, 9.5, INK, "middle", "bold")
            self.text(bx + bw / 2, by + bh + 25, refs, 8.5, SUP, "middle")
        else:
            self.text(bx + bw / 2, by + 17, "÷", 15, INK, "middle", "bold")
            self.text(bx + bw / 2, by + 33, "HV", 7.5, SUP, "middle")
            self.text(bx + bw / 2, by + 42, "LV", 7.5, SUP, "middle")
            off = bw / 2 + 6
            anc, xx = ("start", x + off) if side == "right" else ("end", x - off)
            self.text(xx, (y1 + y2) / 2 - 4, "Divider", 10, INK, anc, "bold")
            self.text(xx, (y1 + y2) / 2 + 9, vals, 9.5, INK, anc)
            self.text(xx, (y1 + y2) / 2 + 21, refs, 8.5, SUP, anc)

    def cap_h(self, x1, x2, y, ref, val, side="below"):
        cx = (x1 + x2) / 2
        self.line(x1, y, cx - 4, y)
        self.line(cx + 4, y, x2, y)
        self.line(cx - 4, y - 11, cx - 4, y + 11, sw=2.2)
        self.line(cx + 4, y - 11, cx + 4, y + 11, sw=2.2)
        if side == "below":
            self.text(cx, y + 26, val, 11, INK, "middle", "bold")
            self.text(cx, y + 37, ref, 9, SUP, "middle")
        else:
            self.text(cx, y - 17, val, 11, INK, "middle", "bold")
            self.text(cx, y - 28, ref, 9, SUP, "middle")

    def rc_h(self, x1, x2, y, rref, rval, cref, cval, dy=26):
        """R (upper branch) in parallel with C (lower branch), horizontal, between (x1, y) and (x2, y)."""
        xa, xb = x1 + 16, x2 - 16
        self.wire([(x1, y), (xa, y)], net=("rch", x1, y))
        self.wire([(xb, y), (x2, y)], net=("rch", x2, y))
        self.line(xa, y - dy, xa, y + dy)
        self.line(xb, y - dy, xb, y + dy)
        self.res_h(xa, xb, y - dy, rref, rval, side="above")
        self.cap_h(xa, xb, y + dy, cref, cval, side="below")
        self.dot(xa, y)
        self.dot(xb, y)

    def box(self, x, y, w, h, title, sub=None, color=SUP):
        self.body.append(
            f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="6" fill="#f3f6fb" '
            f'stroke="{INK}" stroke-width="1.6"/>')
        self.text(x + w / 2, y + 20, title, 12, INK, "middle", "bold")
        if sub:
            self.text(x + w / 2, y + 35, sub, 10, SUP, "middle")

    def diode(self, x, y1, y2, ref, val=None, up=True):
        """Vertical diode, arrow (anode -> cathode) pointing up when up=True; one lead may be dotted."""
        cy = (y1 + y2) / 2
        self.line(x, y1, x, cy - 7)
        self.line(x, cy + 7, x, y2)
        if up:
            tri = f"M{x - 8:g},{cy + 7:g} L{x + 8:g},{cy + 7:g} L{x:g},{cy - 7:g} Z"
            bar = (x - 8, cy - 7, x + 8, cy - 7)
        else:
            tri = f"M{x - 8:g},{cy - 7:g} L{x + 8:g},{cy - 7:g} L{x:g},{cy + 7:g} Z"
            bar = (x - 8, cy + 7, x + 8, cy + 7)
        self.path(tri, sw=1.5, fill="#fff")
        self.line(*bar, sw=1.8)
        self.leads.append((x, y1, cy - 7))
        self.leads.append((x, cy + 7, y2))
        self.text(x + 14, cy + 4, ref + (" " + val if val else ""), 10, SUP)

    def _plabel(self, x, cy, ref, val, side, off):
        if side == "right":
            self.text(x + off, cy + 1, val, 11, INK, "start", "bold")
            self.text(x + off, cy + 13, ref, 9, SUP, "start")
        else:
            self.text(x - off, cy + 1, val, 11, INK, "end", "bold")
            self.text(x - off, cy + 13, ref, 9, SUP, "end")

    # ----------------------------------------------------- rails & pins
    def rail(self, y, x1, x2, label, color=SUP):
        self.line(x1, y, x2, y, stroke=color, sw=2.6, cap="butt")
        self.text(x1 - 8, y + 4, label, 12, color, "end", "bold")

    def gnd(self, x, y):
        """Ground symbol hanging from (x, y)."""
        self.line(x, y, x, y + 7)
        for i, w in enumerate((11, 7, 3)):
            self.line(x - w, y + 7 + i * 4, x + w, y + 7 + i * 4, sw=1.6)

    def vee(self, x, y, label="−50 V"):
        """Negative supply tap: lead down to a bar with label."""
        self.line(x, y, x, y + 6)
        self.line(x - 10, y + 6, x + 10, y + 6, stroke=SUP, sw=2.6, cap="butt")
        self.text(x, y + 20, label, 10, SUP, "middle", "bold")

    def vcc(self, x, y, label="+150 V"):
        self.line(x, y, x, y - 6)
        self.line(x - 10, y - 6, x + 10, y - 6, stroke=SUP, sw=2.6, cap="butt")
        self.text(x, y - 11, label, 10, SUP, "middle", "bold")

    def pin_in(self, x, y, name, sub=None, right=False, color=LV):
        """Input terminal: label on the left (or on the right), the wire leaves on the other side."""
        self.body.append(
            f'<circle cx="{x:g}" cy="{y:g}" r="3.8" fill="#fff" stroke="{color}" stroke-width="1.8"/>')
        dx, anc = (9, "start") if right else (-9, "end")
        self.text(x + dx, y + 4, name, 13, color, anc, "bold")
        if sub:
            self.text(x + dx, y + 16, sub, 8.5, PAD, anc)

    def pin_out(self, x, y, name, color=HV, sub=None, left=False):
        """Output terminal: label on the right (or on the left)."""
        self.body.append(
            f'<circle cx="{x:g}" cy="{y:g}" r="3.8" fill="#fff" stroke="{color}" stroke-width="1.8"/>')
        dx, anc = (-9, "end") if left else (9, "start")
        self.text(x + dx, y + 4, name, 13, color, anc, "bold")
        if sub:
            self.text(x + dx, y + 16, sub, 8.5, PAD, anc)

    def pin_out_up(self, x, y, name, color=HV):
        self.body.append(
            f'<circle cx="{x:g}" cy="{y:g}" r="3.8" fill="#fff" stroke="{color}" stroke-width="1.8"/>')
        self.text(x, y - 8, name, 13, color, "middle", "bold")

    # ------------------------------------------------------------ output
    def _segments(self):
        hs, vs = [], []
        for i, (pts, net, _c, _w) in enumerate(self.wires):
            for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
                if y1 == y2 and x1 != x2:
                    hs.append((i, net, min(x1, x2), max(x1, x2), y1, x1 < x2))
                elif x1 == x2 and y1 != y2:
                    vs.append((i, net, x1, min(y1, y2), max(y1, y2)))
        return hs, vs

    def render(self):
        hs, vs = self._segments()
        out = []
        for i, (pts, net, color, sw) in enumerate(self.wires):
            d = f"M{pts[0][0]:g},{pts[0][1]:g}"
            for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
                if y1 == y2 and x1 != x2:
                    xs = sorted(
                        [v[2] for v in vs
                         if v[1] is not net and v[0] != i and min(x1, x2) + 5 < v[2] < max(x1, x2) - 5
                         and v[3] + 1 < y1 < v[4] - 1]
                        + [lx for (lx, ya, yb) in self.leads
                           if min(x1, x2) + 5 < lx < max(x1, x2) - 5 and ya + 1 < y1 < yb - 1])
                    if x2 < x1:
                        xs.reverse()
                    for hx in xs:
                        s = 1 if x2 > x1 else -1
                        d += f" L{hx - 5 * s:g},{y1:g} a5,5 0 0 {1 if s > 0 else 0} {10 * s:g},0"
                d += f" L{x2:g},{y2:g}"
            out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" '
                       f'stroke-linejoin="round" stroke-linecap="round"/>')
        dots = [f'<circle cx="{x:g}" cy="{y:g}" r="3.4" fill="{c}"/>' for x, y, c in self.dots]
        head = [f'<text x="20" y="28" font-size="17" font-weight="bold" fill="{INK}">{esc(self.title)}</text>']
        if self.sub:
            head.append(f'<text x="20" y="47" font-size="12" fill="{SUP}">{esc(self.sub)}</text>')
        foot = []
        y = self.h - 10 - 14 * (len(self.notes) - 1)
        for n in self.notes:
            foot.append(f'<text x="20" y="{y:g}" font-size="10.5" fill="{SUP}">{esc(n)}</text>')
            y += 14
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
            f'width="{self.w}" height="{self.h}" font-family="{FONT}" role="img" '
            f'aria-label="{esc(self.title)}">\n'
            f'<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>\n'
            + "\n".join(head + self.under + self.body + out + dots + foot) + "\n</svg>\n")
