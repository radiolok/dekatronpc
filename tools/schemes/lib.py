"""Примитивы для структурных схем DekatronPC в inline SVG.

Все цвета берутся из токенов страницы через CSS-классы, внутри SVG
нет ни <style>, ни литеральных цветов. Логические элементы рисуются
прямоугольниками с символом функции по ГОСТ 2.743: «&» — И, «1» — ИЛИ,
кружок на выходе — инверсия.
"""
import html
import math


def esc(s):
    return html.escape(str(s), quote=True)


class Fig:
    def __init__(self, fid, w, h, aria):
        self.id = fid
        self.w = w
        self.h = h
        self.aria = aria
        self.e = []
        self.states = {}
        self.dy = 0

    # ---------------------------------------------------------- базовое
    def add(self, s):
        self.e.append(s)

    def text(self, x, y, t, cls="tl", anchor="start"):
        self.add(f'<text x="{x:g}" y="{y:g}" class="{cls}" text-anchor="{anchor}">{esc(t)}</text>')

    def lines(self, x, y, items, cls="tl", anchor="start", lh=14):
        for i, t in enumerate(items):
            self.text(x, y + i * lh, t, cls, anchor)

    def rect(self, x, y, w, h, cls="blk", rx=2):
        self.add(f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx}" class="{cls}"/>')

    def box(self, x, y, w, h, title=None, body=(), cls="blk", tcls="tt", bcls="tm",
            lh=14, align="middle", pad=10, top=None):
        self.rect(x, y, w, h, cls)
        cy = y + (top if top is not None else 19)
        tx = x + w / 2 if align == "middle" else x + pad
        if title:
            self.text(tx, cy, title, tcls, align)
            cy += lh + 3
        for t in body:
            self.text(tx, cy, t, bcls, align)
            cy += lh

    def frame(self, x, y, w, h, label, cls="frame"):
        """Пунктирная рамка подсистемы с подписью в верхнем левом углу."""
        self.rect(x, y, w, h, cls, rx=4)
        self.text(x + 8, y - 6, label, "tf", "start")

    def marker_ref(self, cls):
        if "warn" in cls:
            return f"{self.id}-aw"
        return f"{self.id}-ag" if "acc" in cls else f"{self.id}-a"

    def wire(self, pts, cls="w", arrow=True, label=None, lx=None, ly=None,
             anchor="start", lcls="tl", start_arrow=False):
        d = " ".join(f"{x:g},{y:g}" for x, y in pts)
        m = f' marker-end="url(#{self.marker_ref(cls)})"' if arrow else ""
        if start_arrow:
            m += f' marker-start="url(#{self.marker_ref(cls)})"'
        self.add(f'<polyline points="{d}" class="{cls}"{m}/>')
        if label is not None:
            self.text(lx, ly, label, lcls, anchor)

    def path(self, d, cls="w", arrow=True, label=None, lx=None, ly=None,
             anchor="middle", lcls="tl"):
        m = f' marker-end="url(#{self.marker_ref(cls)})"' if arrow else ""
        self.add(f'<path d="{d}" class="{cls}"{m}/>')
        if label is not None:
            self.text(lx, ly, label, lcls, anchor)

    def dot(self, x, y, cls="dot"):
        self.add(f'<circle cx="{x:g}" cy="{y:g}" r="2.8" class="{cls}"/>')

    # ------------------------------------------------- логические элементы
    def gate(self, x, y, sym, w=34, h=36, inv=False, name=None, cls="blk"):
        """Элемент по ГОСТ 2.743. Входы: y+10 и y+26, выход: y+h/2."""
        self.rect(x, y, w, h, cls, rx=1)
        self.text(x + w / 2, y + 15, sym, "tg", "middle")
        if inv:
            self.add(f'<circle cx="{x + w + 4:g}" cy="{y + h / 2:g}" r="4" class="inv"/>')
        if name:
            self.text(x + w / 2, y - 5, name, "tn", "middle")

    def pin_in(self, x, y, x2, name, cls="w"):
        """Входной вывод: подпись слева, провод вправо до x2."""
        self.text(x, y - 4, name, "tp", "start")
        self.wire([(x, y), (x2, y)], cls)

    def pin_out(self, x1, y, x2, name, cls="w"):
        self.wire([(x1, y), (x2, y)], cls)
        self.text(x2 + 6, y + 4, name, "tp", "start")

    # ------------------------------------------------------ автоматы
    def state(self, key, cx, cy, name=None, cls="st", w=None, h=34):
        name = name or key
        if w is None:
            w = max(96, 7.4 * len(name) + 26)
        self.states[key] = (cx, cy, w, h)
        self.add(f'<rect x="{cx - w / 2:g}" y="{cy - h / 2:g}" width="{w:g}" height="{h:g}" rx="{h / 2:g}" class="{cls}"/>')
        self.text(cx, cy + 4, name, "ts", "middle")

    def sp(self, key, side, off=0):
        """Точка на стороне состояния: l, r, t, b со смещением вдоль стороны."""
        cx, cy, w, h = self.states[key]
        if side == "l":
            return (cx - w / 2, cy + off)
        if side == "r":
            return (cx + w / 2, cy + off)
        if side == "t":
            return (cx + off, cy - h / 2)
        if side == "b":
            return (cx + off, cy + h / 2)
        raise ValueError(side)

    def edge(self, a, sa, b, sb, via=(), cls="w", label=None, lx=None, ly=None,
             anchor="middle", oa=0, ob=0, lcls="tl"):
        pts = [self.sp(a, sa, oa)] + list(via) + [self.sp(b, sb, ob)]
        self.wire(pts, cls, True, label, lx, ly, anchor, lcls)

    def curve(self, a, sa, b, sb, c1, c2, cls="w", label=None, lx=None, ly=None,
              anchor="middle", oa=0, ob=0, lcls="tl"):
        x1, y1 = self.sp(a, sa, oa)
        x2, y2 = self.sp(b, sb, ob)
        d = f"M{x1:g},{y1:g} C{c1[0]:g},{c1[1]:g} {c2[0]:g},{c2[1]:g} {x2:g},{y2:g}"
        self.path(d, cls, True, label, lx, ly, anchor, lcls)

    def selfloop(self, key, side="t", cls="w", label=None, lx=None, ly=None,
                 anchor="middle", r=26):
        cx, cy, w, h = self.states[key]
        if side == "t":
            x1, y1 = cx - 16, cy - h / 2
            x2, y2 = cx + 16, cy - h / 2
            d = f"M{x1:g},{y1:g} C{x1 - 8:g},{y1 - r * 1.6:g} {x2 + 8:g},{y2 - r * 1.6:g} {x2:g},{y2:g}"
        else:
            x1, y1 = cx - 16, cy + h / 2
            x2, y2 = cx + 16, cy + h / 2
            d = f"M{x1:g},{y1:g} C{x1 - 8:g},{y1 + r * 1.6:g} {x2 + 8:g},{y2 + r * 1.6:g} {x2:g},{y2:g}"
        self.path(d, cls, True, label, lx, ly, anchor)

    # ------------------------------------------------------------ вывод
    def render(self):
        defs = (
            "<defs>"
            f'<marker id="{self.id}-a" viewBox="0 0 10 10" refX="9" refY="5" '
            'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0,1 L10,5 L0,9 z" class="ah"/></marker>'
            f'<marker id="{self.id}-ag" viewBox="0 0 10 10" refX="9" refY="5" '
            'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0,1 L10,5 L0,9 z" class="ahg"/></marker>'
            f'<marker id="{self.id}-aw" viewBox="0 0 10 10" refX="9" refY="5" '
            'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0,1 L10,5 L0,9 z" class="ahw"/></marker>'
            "</defs>"
        )
        mn = min(self.w, 760 if self.w > 600 else 460)
        return (f'<svg viewBox="0 0 {self.w} {self.h}" class="dg" role="img" '
                f'style="width:100%;max-width:{self.w}px;min-width:{mn}px" '
                f'aria-label="{esc(self.aria)}" preserveAspectRatio="xMinYMin meet">'
                f'{defs}<g transform="translate(0,{self.dy})">{"".join(self.e)}</g></svg>')


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)
