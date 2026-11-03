#!/usr/bin/env python3
"""Наброски принципиальных схем обвязки куба КП128/17-М70.

Запуск: python3 sch/fcore/draw_circuits.py
Результат: sch/fcore/img/circuit_key_x.png, circuit_key_y.png,
circuit_write.png, circuit_read.png

Это эскизы до макета: номиналы и типы ламп не проверены расчётом.
"""
import math
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon, Rectangle

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "img")
LW = 1.4
FS = 10.5


class Sheet:
    def __init__(self, w, h, title):
        self.fig, self.ax = plt.subplots(figsize=(w * 0.62, h * 0.62))
        self.ax.set_xlim(0, w)
        self.ax.set_ylim(0, h)
        self.ax.set_aspect("equal")
        self.ax.axis("off")
        self.ax.text(0.2, h - 0.5, title, fontsize=13, fontweight="bold", va="center")

    def wire(self, *pts, ls="-"):
        xs, ys = zip(*pts)
        self.ax.plot(xs, ys, color="k", lw=LW, ls=ls, solid_capstyle="round", zorder=2)

    def dot(self, x, y):
        self.ax.add_patch(Circle((x, y), 0.07, color="k", zorder=4))

    def text(self, x, y, s, ha="left", va="center", fs=FS, color="k"):
        self.ax.text(x, y, s, ha=ha, va=va, fontsize=fs, color=color, zorder=6,
                     linespacing=1.25)

    def rail(self, x, y, name):
        self.wire((x - 0.25, y), (x + 0.25, y))
        self.text(x, y + 0.08, name, ha="center", va="bottom")

    def gnd(self, x, y):
        for i, half in enumerate((0.28, 0.17, 0.07)):
            yy = y - i * 0.09
            self.wire((x - half, yy), (x + half, yy))

    def res(self, x1, y1, x2, y2, name=None, side=1):
        """Резистор по ГОСТ на вертикальном или горизонтальном отрезке."""
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        if x1 == x2:
            lo, hi = sorted((y1, y2))
            self.wire((x1, lo), (x1, cy - 0.35))
            self.wire((x1, cy + 0.35), (x1, hi))
            self.ax.add_patch(Rectangle((x1 - 0.13, cy - 0.35), 0.26, 0.7, fill=True,
                                        fc="w", ec="k", lw=LW, zorder=3))
            if name:
                self.text(x1 + side * 0.22, cy, name, ha="left" if side > 0 else "right")
        else:
            lo, hi = sorted((x1, x2))
            self.wire((lo, y1), (cx - 0.35, y1))
            self.wire((cx + 0.35, y1), (hi, y1))
            self.ax.add_patch(Rectangle((cx - 0.35, y1 - 0.13), 0.7, 0.26, fill=True,
                                        fc="w", ec="k", lw=LW, zorder=3))
            if name:
                self.text(cx, y1 + side * 0.22, name, ha="center",
                          va="bottom" if side > 0 else "top")

    def cap(self, x1, y1, x2, y2, name=None, side=1):
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        if x1 == x2:
            lo, hi = sorted((y1, y2))
            self.wire((x1, lo), (x1, cy - 0.07))
            self.wire((x1, cy + 0.07), (x1, hi))
            self.wire((x1 - 0.22, cy - 0.07), (x1 + 0.22, cy - 0.07))
            self.wire((x1 - 0.22, cy + 0.07), (x1 + 0.22, cy + 0.07))
            if name:
                self.text(x1 + side * 0.3, cy, name, ha="left" if side > 0 else "right")
        else:
            lo, hi = sorted((x1, x2))
            self.wire((lo, y1), (cx - 0.07, y1))
            self.wire((cx + 0.07, y1), (hi, y1))
            self.wire((cx - 0.07, y1 - 0.22), (cx - 0.07, y1 + 0.22))
            self.wire((cx + 0.07, y1 - 0.22), (cx + 0.07, y1 + 0.22))
            if name:
                self.text(cx, y1 + side * 0.3, name, ha="center",
                          va="bottom" if side > 0 else "top")

    def diode(self, x1, y1, x2, y2, name=None, side=1):
        """Диод, анод в (x1, y1), катод в (x2, y2)."""
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        length = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / length, (y2 - y1) / length
        nx, ny = -uy, ux
        s = 0.2
        ax, ay = cx - ux * s, cy - uy * s
        kx, ky = cx + ux * s, cy + uy * s
        self.wire((x1, y1), (ax, ay))
        self.wire((kx, ky), (x2, y2))
        self.ax.add_patch(Polygon([(ax + nx * s, ay + ny * s), (ax - nx * s, ay - ny * s), (kx, ky)],
                                  closed=True, fc="w", ec="k", lw=LW, zorder=3))
        self.wire((kx + nx * s, ky + ny * s), (kx - nx * s, ky - ny * s))
        if name:
            if x1 == x2:
                self.text(cx + side * 0.32, cy, name, ha="left" if side > 0 else "right")
            else:
                self.text(cx, cy + side * 0.32, name, ha="center",
                          va="bottom" if side > 0 else "top")

    def coil(self, x, y_top, turns, right=True, pitch=0.3):
        """Вертикальная обмотка: выпуклость вправо или влево. Возвращает нижнюю координату."""
        sign = 1 if right else -1
        y = y_top
        for _ in range(turns):
            ts = [math.pi / 2 - math.pi * i / 16 for i in range(17)]
            xs = [x + sign * pitch / 2 * math.cos(t) for t in ts]
            ys = [y - pitch / 2 + pitch / 2 * math.sin(t) for t in ts]
            self.ax.plot(xs, ys, color="k", lw=LW, zorder=3)
            y -= pitch
        return y

    def core(self, x, y1, y2):
        self.wire((x - 0.05, y1), (x - 0.05, y2))
        self.wire((x + 0.05, y1), (x + 0.05, y2))

    def triode(self, cx, cy, name, note=None, name_left=False):
        """Возвращает выводы: анод, сетка, катод."""
        r = 0.62
        self.ax.add_patch(Circle((cx, cy), r, fc="w", ec="k", lw=LW, zorder=3))
        self.ax.plot([cx - 0.28, cx + 0.28], [cy + 0.28, cy + 0.28], color="k", lw=LW, zorder=4)
        self.ax.plot([cx - 0.28, cx + 0.28], [cy, cy], color="k", lw=LW, ls=(0, (2, 2)), zorder=4)
        self.ax.plot([cx - 0.25, cx - 0.25, cx + 0.25, cx + 0.25],
                     [cy - 0.22, cy - 0.32, cy - 0.32, cy - 0.22], color="k", lw=LW, zorder=4)
        self.ax.plot([cx, cx], [cy + 0.28, cy + r], color="k", lw=LW, zorder=4)
        self.ax.plot([cx - r, cx - 0.28], [cy, cy], color="k", lw=LW, zorder=4)
        self.ax.plot([cx, cx], [cy - 0.32, cy - r], color="k", lw=LW, zorder=4)
        label = name if note is None else name + "\n" + note
        if name_left:
            self.text(cx - 0.75, cy + 0.85, label, ha="right")
        else:
            self.text(cx + 0.75, cy + 0.1, label)
        return (cx, cy + r), (cx - r, cy), (cx, cy - r)

    def pentode(self, cx, cy, name, note=None):
        """Возвращает выводы: анод, g1, g2, g3, катод."""
        r = 0.8
        self.ax.add_patch(Circle((cx, cy), r, fc="w", ec="k", lw=LW, zorder=3))
        self.ax.plot([cx - 0.3, cx + 0.3], [cy + 0.45, cy + 0.45], color="k", lw=LW, zorder=4)
        for dy in (0.25, 0.02, -0.21):
            self.ax.plot([cx - 0.35, cx + 0.35], [cy + dy, cy + dy], color="k", lw=LW,
                         ls=(0, (2, 2)), zorder=4)
        self.ax.plot([cx - 0.28, cx - 0.28, cx + 0.28, cx + 0.28],
                     [cy - 0.42, cy - 0.52, cy - 0.52, cy - 0.42], color="k", lw=LW, zorder=4)
        self.ax.plot([cx, cx], [cy + 0.45, cy + r], color="k", lw=LW, zorder=4)
        self.ax.plot([cx, cx], [cy - 0.52, cy - r], color="k", lw=LW, zorder=4)
        # g1 — средняя слева, g3 — нижняя слева, g2 — верхняя справа
        self.ax.plot([cx - r, cx - 0.35], [cy + 0.02, cy + 0.02], color="k", lw=LW, zorder=4)
        self.ax.plot([cx - 0.73, cx - 0.35], [cy - 0.32, cy - 0.21], color="k", lw=LW, zorder=4)
        self.ax.plot([cx + 0.35, cx + 0.76], [cy + 0.25, cy + 0.25], color="k", lw=LW, zorder=4)
        label = name if note is None else name + "\n" + note
        self.text(cx + 0.95, cy - 0.32, label)
        return ((cx, cy + r), (cx - r, cy + 0.02), (cx + 0.76, cy + 0.25),
                (cx - 0.73, cy - 0.32), (cx, cy - r))

    def box(self, x, y, w, h, lines, fill=None, fs=FS):
        self.ax.add_patch(Rectangle((x, y), w, h, fc=fill or "w", ec="k", lw=LW, zorder=3))
        self.text(x + w / 2, y + h / 2, lines, ha="center", fs=fs)

    def port(self, x, y, s, side="left"):
        self.text(x, y, s, ha="right" if side == "left" else "left")

    def save(self, name, note=None):
        if note:
            self.text(0.2, 0.55, note, va="center", fs=9.5, color="#333333")
        self.fig.savefig(os.path.join(OUT, name), dpi=170, bbox_inches="tight", pad_inches=0.12,
                         facecolor="white")
        plt.close(self.fig)


def key_stage(s, x, y_tube, y_top, label, tube="V1", t="T1"):
    """Лампа с импульсным трансформатором в аноде.

    Возвращает верх и низ вторичной обмотки и координату x её вывода.
    """
    a, g, k = s.triode(x, y_tube, tube, "6Н16Б,\nоба триода\nпараллельно", name_left=False)
    s.gnd(k[0], k[1] - 0.3)
    s.wire(k, (k[0], k[1] - 0.3))
    # первичная обмотка
    px = x + 2.6
    bottom = s.coil(px, y_top - 0.6, 6, right=True)
    s.wire(a, (a[0], y_top - 2.9), (px, y_top - 2.9), (px, bottom))
    s.wire((px, y_top - 0.6), (px, y_top))
    s.rail(px, y_top, "+Ua")
    # демпфер первичной обмотки
    dx = px - 1.1
    s.wire((px, y_top - 0.3), (dx, y_top - 0.3))
    s.diode(dx, y_top - 2.0, dx, y_top - 1.15, "Д1\n6Х7Б", side=-1)
    s.res(dx, y_top - 1.15, dx, y_top - 0.3, "R1", side=-1)
    s.wire((dx, y_top - 2.0), (dx, y_top - 2.9))
    s.dot(dx, y_top - 2.9)
    # сердечник и вторичная
    s.core(px + 0.42, y_top - 0.4, bottom - 0.2)
    sx = px + 0.84
    sbot = s.coil(sx, y_top - 0.9, 2, right=False)
    s.text(px + 0.6, y_top - 0.25, t + " 5:1", ha="left")
    return g, sx, y_top - 0.9, sbot


def draw_key_x():
    s = Sheet(21, 10.4, "Ключ линии X (одна из 8)")
    s.box(0.5, 3.1, 3.0, 1.5, "И:\nлиния Xn\n· импульс X/Y")
    s.port(0.4, 4.15, "Xn")
    s.port(0.4, 3.55, "имп.")
    g, sx, st, sb = key_stage(s, 5.6, 3.85, 9.0, "X")
    s.res(3.5, 3.85, g[0], 3.85, "R2", side=1)
    # RC-цепочка, диод
    y = st
    s.wire((sx, y), (sx + 0.5, y))
    s.diode(sx + 0.5, y, sx + 1.5, y, "Д2 Ge", side=1)
    x0, x1 = sx + 1.5, sx + 3.3
    s.res(x0, y, x1, y, "R3", side=1)
    s.wire((x0, y), (x0, y - 0.8))
    s.cap(x0, y - 0.8, x1, y - 0.8, "C1", side=-1)
    s.wire((x1, y - 0.8), (x1, y))
    # обмотки куба
    bx = x1 + 0.4
    s.box(bx, y - 0.45, 1.5, 0.9, "X′")
    s.wire((x1, y), (bx, y))
    s.box(bx + 2.0, y - 0.45, 1.5, 0.9, "X″")
    s.wire((bx + 1.5, y), (bx + 2.0, y))
    s.text(bx + 1.75, y + 0.75, "куб 1", ha="center")
    # следующий куб и обратная цепь
    ex = bx + 3.5
    s.wire((ex, y), (ex + 0.3, y))
    s.text(ex + 0.35, y, "… все\nкубы блока", fs=9.5)
    s.wire((ex + 0.3, y), (ex + 0.3, y - 2.5))
    s.wire((ex + 0.3, y - 2.5), (sx, y - 2.5), (sx, sb))
    s.text((sx + ex) / 2, y - 2.7, "обратный провод вместе с прямым, в жгуте", ha="center", va="top", fs=9.5)
    s.text(sx + 1.5, y + 1.25, "около 183 мА, от 10 ± 2 В на куб", fs=9.5)
    s.save("circuit_key_x.png",
           "Эскиз до макета. Импульс в аноде около 37 мА при 5:1. Д2 не пускает обратный ход в линию: спад ведёт смещение CM.\n"
           "R3 и C1 — цепочка рис. 47: сначала источник напряжения, затем ограничение тока.")


def draw_key_y():
    s = Sheet(25, 14.6, "Ключ линии Y (одна из 16) и выбор куба")
    s.box(0.5, 7.8, 3.0, 1.5, "И:\nлиния Yn\n· импульс X/Y")
    s.port(0.4, 8.85, "Yn")
    s.port(0.4, 8.25, "имп.")
    g, sx, st, sb = key_stage(s, 5.6, 8.55, 13.6, "Y")
    s.res(3.5, 8.55, g[0], 8.55, "R2", side=1)
    y = st
    x0, x1 = sx + 0.4, sx + 2.2
    s.wire((sx, y), (x0, y))
    s.res(x0, y, x1, y, "R3", side=1)
    s.wire((x0, y), (x0, y - 0.8))
    s.cap(x0, y - 0.8, x1, y - 0.8, "C1", side=-1)
    s.wire((x1, y - 0.8), (x1, y))
    c1 = x1 + 2.6
    c2 = c1 + 6.2
    s.wire((x1, y), (c2 + 1.2, y))
    s.text(c2 + 1.3, y, "шина Yn\n… кубы", fs=9.5)
    y_join = y - 3.0
    y_bus = 2.1

    def module(cx, label):
        s.dot(cx, y)
        s.diode(cx, y, cx, y - 1.4, "Д3 Ge", side=1)
        s.box(cx - 0.75, y - 2.4, 1.5, 0.9, "Yn")
        s.wire((cx, y - 1.4), (cx, y - 1.5))
        s.text(cx + 0.85, y - 1.95, label, fs=9.5)
        s.wire((cx, y - 2.4), (cx, y_join))
        s.dot(cx, y_join)
        s.text(cx + 0.12, y_join + 0.22, "общая точка Y куба", fs=9.5)

    def select(cx, tube, t_name, sel):
        y_coil = y_join - 0.9
        s.wire((cx, y_join), (cx, y_coil))
        bot = s.coil(cx, y_coil, 2, right=False)
        s.wire((cx, bot), (cx, bot - 0.2), (cx - 2.7, bot - 0.2), (cx - 2.7, y_bus))
        s.dot(cx - 2.7, y_bus)
        s.core(cx + 0.42, y_coil + 0.1, y_coil - 1.9)
        px = cx + 0.84
        pbot = s.coil(px, y_coil - 0.2, 5, right=True)
        s.text(cx + 0.14, y_coil + 0.34, t_name + " 5:1", fs=9.5)
        s.wire((px, y_coil - 0.2), (px + 0.9, y_coil - 0.2), (px + 0.9, y_coil + 0.2))
        s.rail(px + 0.9, y_coil + 0.2, "+Ua")
        a, gg, k = s.triode(px, pbot - 1.1, tube, "6Н16Б")
        s.wire((px, pbot), a)
        s.wire(k, (k[0], k[1] - 0.25))
        s.gnd(k[0], k[1] - 0.25)
        s.wire((gg[0] - 0.3, gg[1]), gg)
        s.text(gg[0] - 0.35, gg[1], sel + "\n· импульс", ha="right", fs=9.5)

    module(c1, "куб 1")
    module(c2, "куб 2")
    select(c1, "V2", "T2", "выбор куба 1")
    select(c2, "V3", "T3", "выбор куба 2")
    s.wire((sx, sb), (sx, y_bus), (c2 - 2.7, y_bus))
    s.text(sx + 0.2, y_bus - 0.2, "общий обратный провод, в жгуте с шиной Yn", va="top", fs=9.5)
    s.save("circuit_key_y.png",
           "Эскиз до макета. Возвратный ключ тоже идёт через трансформатор: прямо в цепи 10 В лампа не пропустит 183 мА. Импульс на кубе дают две вторичные обмотки\n"
           "последовательно; напряжение между T1 и T2 делим на макете. Д3 развязывают невыбранные кубы. Шины X, CM и P здесь не показаны.")


def draw_write():
    s = Sheet(21, 11.2, "Запись: разрядный канал одного бита")
    s.box(0.5, 6.5, 3.0, 1.7, "Выбор знака:\nwr ? wr_data\n: rd_data")
    s.port(0.4, 7.75, "wr, wr_data")
    s.port(0.4, 7.0, "rd_data")
    s.box(4.4, 7.6, 2.6, 1.3, "И:\nзнак · фаза\nзаписи")
    s.box(4.4, 3.3, 2.6, 1.3, "И:\nне знак · фаза\nзаписи")
    s.wire((3.5, 7.35), (3.95, 7.35), (3.95, 8.25), (4.4, 8.25))
    s.wire((3.95, 7.35), (3.95, 3.95), (4.4, 3.95))
    s.text(4.1, 5.6, "(не)", fs=9.5)
    a1, g1, k1 = s.triode(9.0, 8.25, "V1а", "6Н16Б", name_left=True)
    a2, g2, k2 = s.triode(9.0, 3.95, "V1б", "6Н16Б", name_left=True)
    s.wire((7.0, 8.25), g1)
    s.wire((7.0, 3.95), g2)
    s.gnd(9.0, 7.35)
    s.wire(k1, (9.0, 7.35))
    s.gnd(9.0, 3.05)
    s.wire(k2, (9.0, 3.05))
    # двухтактная первичная
    px = 12.0
    top = 7.7
    mid = s.coil(px, top, 5, right=True)
    bot = s.coil(px, mid, 5, right=True)
    s.wire(a1, (9.0, 9.35), (px, 9.35), (px, top))
    s.wire(a2, (9.0, 5.1), (10.6, 5.1), (10.6, bot), (px, bot))
    s.dot(px, mid)
    s.wire((px, mid), (11.0, mid), (11.0, 7.3))
    s.rail(11.0, 7.3, "+Ua")
    s.core(px + 0.42, top + 0.2, bot - 0.2)
    s.text(px + 0.42, top + 0.3, "T4  5+5:1", ha="center", va="bottom")
    # вторичная к P
    sx = px + 0.84
    sbot = s.coil(sx, 6.9, 2, right=False)
    s.res(sx, 6.9, sx + 2.0, 6.9, "R1", side=1)
    s.wire((sx, 6.9), (sx, 6.9))
    bx = sx + 2.0
    s.box(bx, 6.45, 1.5, 0.9, "P куб 1")
    s.wire((bx + 1.5, 6.9), (bx + 2.1, 6.9))
    s.text(bx + 2.15, 6.9, "… P\nвсех кубов", fs=9.5)
    s.wire((bx + 2.1, 6.9), (bx + 2.1, sbot), (sx, sbot))
    s.text(sx + 1.0, 8.0, "±50 ± 10 мА", fs=9.5)
    # обмотка чтения
    rx = sx
    s.wire((rx, 4.7), (rx + 0.7, 4.7))
    rbot = s.coil(rx, 4.7, 4, right=False)
    s.wire((rx, rbot), (rx + 0.7, rbot))
    s.text(rx + 0.8, (4.7 + rbot) / 2, "обмотка чтения,\nк усилителю (см. схему чтения)", fs=9.5)
    s.save("circuit_write.png",
           "Эскиз до макета. Анодный ток около 10 мА при 5:1. Включён один из двух триодов: знак тока задаёт бит. На фазе записи (фазы 4–6) ток идёт через P;\n"
           "R1 ограничивает ток. T4 общий для записи и чтения, поэтому обмотка P одна, а вход усилителя при записи защищён ограничителем.")


def draw_read():
    s = Sheet(28, 12.0, "Чтение: разрядный канал одного бита")
    # обмотка чтения T4
    s.text(0.3, 7.7, "Обмотка P\n(см. схему\nзаписи)", fs=9.5)
    x = 3.6
    s.core(x - 0.42, 9.2, 6.0)
    s.wire((x - 1.1, 8.9), (x - 0.84, 8.9), (x - 0.84, 8.4))
    b = s.coil(x - 0.84, 8.4, 2, right=True)
    s.wire((x - 0.84, b), (x - 0.84, 6.6), (x - 1.1, 6.6))
    top = 9.0
    bot = s.coil(x, top, 8, right=False)
    s.text(x - 0.42, 9.3, "T4  1:10", ha="center", va="bottom")
    s.wire((x, top), (x, 9.4), (x + 3.4, 9.4))
    s.wire((x, bot), (x, 5.2))
    s.gnd(x, 5.2)
    # нагрузка и ограничитель
    x1 = x + 1.2
    s.dot(x1, 9.4)
    s.res(x1, 9.4, x1, 6.0, "R1 10 к", side=1)
    s.gnd(x1, 6.0)
    x2 = x + 3.0
    s.dot(x2, 9.4)
    s.diode(x2, 9.4, x2, 8.2)
    s.diode(x2 + 0.7, 8.2, x2 + 0.7, 9.4)
    s.wire((x2, 9.4), (x2 + 0.7, 9.4))
    s.wire((x2, 8.2), (x2 + 0.7, 8.2))
    s.dot(x2 + 0.35, 8.2)
    s.wire((x2 + 0.35, 8.2), (x2 + 0.35, 7.7))
    s.gnd(x2 + 0.35, 7.7)
    s.text(x2 + 0.9, 8.0, "Д1, Д2 Ge", va="top", fs=9.5)
    # первый каскад
    s.cap(x2 + 0.7, 9.4, x2 + 2.0, 9.4, "C1", side=1)
    n1 = x2 + 3.0
    s.wire((x2 + 2.0, 9.4), (n1 - 0.62, 9.4), (n1 - 0.62, 7.0))
    s.wire((n1 - 0.62, 7.0), (n1 - 0.62, 7.0))
    a, g, k = s.triode(n1 + 0.0, 7.0, "V1", "6Н16Б\nили нувистор")
    s.res(n1 - 0.62, 7.0, n1 - 0.62, 5.0, "R2", side=-1)
    s.gnd(n1 - 0.62, 5.0)
    s.res(n1, k[1], n1, 5.0, "R3", side=1)
    s.gnd(n1, 5.0)
    s.res(n1, a[1], n1, 10.6, "Ra1", side=1)
    s.rail(n1, 10.6, "+Ua")
    # второй каскад
    n2 = n1 + 4.3
    s.dot(n1, 8.2)
    s.cap(n1, 8.2, n2 - 1.3, 8.2, "C2", side=1)
    a2, g1, g2, g3, k2 = s.pentode(n2, 7.0, "V2", "6Ж2Б")
    s.wire((n2 - 1.3, 8.2), (n2 - 1.3, g1[1]), g1)
    s.res(n2 - 1.3, g1[1], n2 - 1.3, 5.0, "R4", side=-1)
    s.gnd(n2 - 1.3, 5.0)
    s.wire(k2, (n2, 5.0))
    s.gnd(n2, 5.0)
    s.wire(g3, (g3[0], 5.5), (n2, 5.5))
    s.dot(n2, 5.5)
    s.res(n2, a2[1], n2, 10.6, "Ra2", side=1)
    s.rail(n2, 10.6, "+Ua")
    s.wire(g2, (g2[0] + 0.35, g2[1]), (g2[0] + 0.35, 10.6))
    s.rail(g2[0] + 0.35, 10.6, "+Ug2")
    # строб
    n3 = n2 + 5.2
    s.dot(n2, 8.4)
    s.cap(n2, 8.4, n3 - 1.3, 8.4, "C3", side=1)
    a3, h1, h2, h3, k3 = s.pentode(n3, 7.0, "V3", "6Ж2Б")
    s.wire((n3 - 1.3, 8.4), (n3 - 1.3, h1[1]), h1)
    s.res(n3 - 1.3, h1[1], n3 - 1.3, 5.0, "R5", side=-1)
    s.gnd(n3 - 1.3, 5.0)
    s.wire(k3, (n3, 5.0))
    s.gnd(n3, 5.0)
    s.res(n3, a3[1], n3, 10.6, "Ra3", side=1)
    s.rail(n3, 10.6, "+Ua")
    s.wire(h2, (h2[0] + 0.35, h2[1]), (h2[0] + 0.35, 10.6))
    s.rail(h2[0] + 0.35, 10.6, "+Ug2")
    s.wire(h3, (h3[0], 3.6))
    s.text(h3[0], 3.5, "строб (фаза 3), на g3", ha="center", va="top")
    # защёлка
    lx = n3 + 2.6
    s.dot(n3, 8.6)
    s.wire((n3, 8.6), (lx, 8.6))
    s.box(lx, 6.9, 2.3, 2.2, "Защёлка\nRSLATCH\n_J2N16", fs=9.5)
    s.wire((lx + 2.3, 8.0), (lx + 3.0, 8.0))
    s.text(lx + 3.05, 8.0, "rd_data")
    s.wire((lx + 1.15, 6.9), (lx + 1.15, 5.9))
    s.text(lx + 1.15, 5.8, "сброс\n(фаза 1)", ha="center", va="top")
    s.save("circuit_read.png",
           "Эскиз до макета. 7 мВ на P дают около 70 мВ на R1; 10 кОм при 1:10 пересчитываются в 100 Ом на стороне P, паспорт требует не менее 95 Ом.\n"
           "Сигнал двуполярный: строб V3 защёлкивает только полярность единицы, ноль оставляет защёлку сброшенной. Какая полярность единица и нужная полярность\n"
           "на S определяются на макете. Д1 и Д2 ограничивают импульс записи; восстановление усилителя к следующему циклу надо проверить.")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    draw_key_x()
    draw_key_y()
    draw_write()
    draw_read()
