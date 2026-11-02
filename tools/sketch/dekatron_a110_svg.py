#!/usr/bin/env python3
"""Эскизы декатронного модуля А110 с катодными лампами записи.

Рисует SVG для страницы sch/logic/DEKATRON_A110/README.md:
  dek_a110_board.svg  — структурная схема платы декатрона и соседних плат;
  dek_a110_write.svg  — декада с записью (счётчик данных): 10 каналов записи;
  dek_a110_reset.svg  — декады только со сбросом: 2 (или 3) канала записи.

Это эскиз, не схема KiCad: номиналы — из SPICE (tools/spice/dek_module_tb.py, §9 страницы),
параметры А110 — оценки (OPEN-013). Состав плат — TRS v0.38–v0.40.
Запуск: python3 tools/sketch/dekatron_a110_svg.py [OUT_DIR]
(по умолчанию OUT_DIR = sch/logic/DEKATRON_A110/img).
"""
import math
import os
import sys

INK = "#111"
PROP = "#c05000"      # то, что предлагаю добавить к идее владельца
NOTE = "#555"
FONT = "font-family='DejaVu Sans, Arial, sans-serif'"


class Svg:
    def __init__(self, w, h, title):
        self.w, self.h = w, h
        self.items = [f"<title>{title}</title>",
                      f"<rect x='0' y='0' width='{w}' height='{h}' fill='white'/>"]

    def line(self, pts, color=INK, dash=False, width=1.5):
        d = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        da = " stroke-dasharray='6,4'" if dash else ""
        self.items.append(f"<polyline points='{d}' fill='none' stroke='{color}' "
                          f"stroke-width='{width}'{da}/>")

    def text(self, x, y, s, size=13, anchor="start", color=INK, bold=False, italic=False):
        fw = " font-weight='bold'" if bold else ""
        fs = " font-style='italic'" if italic else ""
        self.items.append(f"<text x='{x:.1f}' y='{y:.1f}' {FONT} font-size='{size}' "
                          f"text-anchor='{anchor}' fill='{color}'{fw}{fs}>{s}</text>")

    def dot(self, x, y, color=INK):
        self.items.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='3.2' fill='{color}'/>")

    def circle(self, x, y, r, color=INK, width=1.5, fill="none"):
        self.items.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{r}' fill='{fill}' "
                          f"stroke='{color}' stroke-width='{width}'/>")

    def rect(self, x, y, w, h, color=INK, dash=False, fill="none", width=1.5):
        da = " stroke-dasharray='6,4'" if dash else ""
        self.items.append(f"<rect x='{x:.1f}' y='{y:.1f}' width='{w}' height='{h}' "
                          f"fill='{fill}' stroke='{color}' stroke-width='{width}'{da}/>")

    # --- элементы ---------------------------------------------------------
    def res_v(self, x, y1, y2, label="", color=INK, dash=False, side=1):
        """Вертикальный резистор между y1 и y2 (y1 < y2)."""
        m = (y1 + y2) / 2
        self.line([(x, y1), (x, m - 18)], color, dash)
        self.rect(x - 5, m - 18, 10, 36, color, dash)
        self.line([(x, m + 18), (x, y2)], color, dash)
        if label:
            self.text(x + side * 9, m + 4, label, 11, "start" if side > 0 else "end", color)

    def cap_v(self, x, y1, y2, label="", color=INK, side=1):
        m = (y1 + y2) / 2
        self.line([(x, y1), (x, m - 4)], color)
        self.line([(x - 10, m - 4), (x + 10, m - 4)], color, width=2)
        self.line([(x - 10, m + 4), (x + 10, m + 4)], color, width=2)
        self.line([(x, m + 4), (x, y2)], color)
        if label:
            self.text(x + side * 14, m + 4, label, 11, "start" if side > 0 else "end", color)

    def cap_h(self, x1, x2, y, label="", color=INK):
        m = (x1 + x2) / 2
        self.line([(x1, y), (m - 4, y)], color)
        self.line([(m - 4, y - 10), (m - 4, y + 10)], color, width=2)
        self.line([(m + 4, y - 10), (m + 4, y + 10)], color, width=2)
        self.line([(m + 4, y), (x2, y)], color)
        if label:
            self.text(m, y - 14, label, 11, "middle", color)

    def tag_up(self, x, y, s, color=INK):
        """Вывод на шину питания вверх: T-образная метка."""
        self.line([(x - 9, y), (x + 9, y)], color, width=2)
        self.text(x, y - 5, s, 11, "middle", color)

    def tag_down(self, x, y, s, color=INK):
        self.line([(x - 9, y), (x + 9, y)], color, width=2)
        self.text(x, y + 15, s, 11, "middle", color)

    def triode(self, x, y, grid_side=-1, grid_len=22, label="", color=INK):
        """Триод, центр (x, y). Анод сверху (x, y-18), катод снизу (x, y+18),
        сетка — вывод в сторону grid_side, конец (x+grid_side*(18+grid_len), y).
        Возвращает координаты конца вывода сетки."""
        r = 18
        self.circle(x, y, r, color)
        self.line([(x - 8, y - 8), (x + 8, y - 8)], color, width=2)     # анод
        self.line([(x, y - 8), (x, y - r)], color)
        self.line([(x - 9, y), (x + 9, y)], color, dash=True, width=1.2)  # сетка
        gx = x + grid_side * (r + grid_len)
        self.line([(x + grid_side * 9, y), (gx, y)], color)
        self.line([(x - 8, y + 9), (x + 8, y + 9)], color, width=2)     # катод
        self.line([(x, y + 9), (x, y + r)], color)
        if label:
            self.text(x - grid_side * 22, y + 4, label, 11,
                      "start" if grid_side < 0 else "end", color)
        return gx, y

    def pentode(self, x, y, grid_side=-1, grid_len=26, label="", color=INK):
        """Пентод: анод сверху, катод снизу, g1 (y-1) и g3 (y+6) в сторону grid_side.
        g2 не рисуется (на +150 В). Возвращает концы выводов g1, g3."""
        r = 20
        self.circle(x, y, r, color)
        self.line([(x - 9, y - 11), (x + 9, y - 11)], color, width=2)
        self.line([(x, y - 11), (x, y - r)], color)
        g = []
        for dy in (-3, 5):
            self.line([(x - 10, y + dy), (x + 10, y + dy)], color, dash=True, width=1.2)
            gx = x + grid_side * (r + grid_len)
            self.line([(x + grid_side * 10, y + dy), (gx, y + dy)], color)
            g.append((gx, y + dy))
        self.line([(x - 9, y + 13), (x + 9, y + 13)], color, width=2)
        self.line([(x, y + 13), (x, y + r)], color)
        if label:
            self.text(x - grid_side * 26, y + 4, label, 11,
                      "start" if grid_side < 0 else "end", color)
        return g

    def arrow_out(self, x, y, s, side=-1, color=INK):
        """Выход-метка (линия чтения): стрелка наружу от узла."""
        x2 = x + side * 26
        self.line([(x, y), (x2, y)], color)
        self.line([(x2 + side * -6, y - 4), (x2, y), (x2 + side * -6, y + 4)], color)
        self.text(x2 + side * 3, y + 4, s, 11, "end" if side < 0 else "start", color)

    def dekatron(self, cx, cy, r=66, label="А110"):
        self.circle(cx, cy, r, INK, 2)
        # кольцо из 30 электродов: катоды — крупные точки, подкатоды — мелкие
        for k in range(30):
            a = math.radians(90 + 180 / 30 + k * 12)
            px, py = cx + 0.70 * r * math.cos(a), cy + 0.70 * r * math.sin(a)
            rr = 3.6 if k % 3 == 0 else 1.8
            self.items.append(f"<circle cx='{px:.1f}' cy='{py:.1f}' r='{rr}' fill='{INK}'/>")
        self.circle(cx, cy, 0.32 * r, INK, 1.2)
        self.text(cx, cy + 5, label, 13, "middle", bold=True)

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(f"<svg xmlns='http://www.w3.org/2000/svg' width='{self.w}' "
                    f"height='{self.h}' viewBox='0 0 {self.w} {self.h}'>\n")
            f.write("\n".join(self.items))
            f.write("\n</svg>\n")


def cathode_pin(cx, cy, r, i, n=10, span=118):
    """Точка вывода катода i на нижней дуге баллона (K0 слева)."""
    a = math.radians(90 + span / 2 - i * span / (n - 1))
    return cx + r * math.cos(a), cy + r * math.sin(a)


def diode_up(s, x, y1, y2, label="", color=INK, dash=True):
    """Диод между y1 (катод, сверху) и y2 (анод, снизу): ток снизу вверх."""
    m = (y1 + y2) / 2
    s.line([(x, y1), (x, m - 7)], color, dash)
    s.line([(x - 8, m - 7), (x + 8, m - 7)], color, width=2)
    s.items.append(f"<polygon points='{x - 8},{m + 7} {x + 8},{m + 7} {x},{m - 7}' "
                   f"fill='none' stroke='{color}' stroke-width='1.5'/>")
    s.line([(x, m + 7), (x, y2)], color, dash)
    if label:
        s.text(x - 12, m + 4, label, 10, "end", color)


def diode_h(s, x_a, x_k, y, color=INK):
    """Диод по горизонтали: анод в x_a, катод в x_k (треугольник смотрит на катод)."""
    d = 1 if x_k > x_a else -1
    m = (x_a + x_k) / 2
    s.line([(x_a, y), (m - d * 7, y)], color)
    s.items.append(f"<polygon points='{m - d * 7},{y - 7} {m - d * 7},{y + 7} {m + d * 7},{y}' "
                   f"fill='none' stroke='{color}' stroke-width='1.5'/>")
    s.line([(m + d * 7, y - 7), (m + d * 7, y + 7)], color, width=2)
    s.line([(m + d * 7, y), (x_k, y)], color)


def board_split(s, x1, x2, y, above, below):
    """Граница плат: штрихпунктир с подписями сверху и снизу."""
    s.items.append(f"<polyline points='{x1},{y} {x2},{y}' fill='none' stroke='{NOTE}' "
                   f"stroke-width='1.2' stroke-dasharray='14,4,3,4'/>")
    s.text(x2, y - 6, above, 11, "end", NOTE, italic=True)
    s.text(x2, y + 15, below, 11, "end", NOTE, italic=True)


def read_tap(s, x, y, i, up=34):
    """Диод чтения: ½ 6Х7Б от узла сетки (подтяжка 100k к +5 В) к катодной линии."""
    gx = x - 52
    diode_h(s, gx, x, y)
    s.dot(gx, y)
    s.res_v(gx, y - up, y, "")
    s.tag_up(gx, y - up, "+5")
    s.line([(gx, y), (gx - 18, y)])
    s.text(gx - 20, y + 4, f"чт{i}", 10, "end")


def anode_and_guides(s, cx, cy, r, keys=True):
    """Анод с Rа и цепи подкатодов по Яблонскому (рис. 3-1, 3-4, 4-8):
    ключ GUIDE_EN_J2 (катод на земле) -> Cп -> подкатод; смещение через Rсм
    от делителя Uсм; восстанавливающий диод ½ 6Х7Б параллельно Rсм."""
    s.tag_up(cx, 62, "+350 В")
    s.res_v(cx, 62, cy - r, "Rа 180…220k")
    s.text(cx - 8, cy - r - 4, "A", 11, "end")
    if not keys:
        return
    for side, name, bus in ((-1, "ПК1", "GuideA"), (1, "ПК2", "GuideB")):
        px = cx + side * r
        gx = cx + side * 150          # узел подкатода
        kx = cx + side * 290          # анод ключа
        gy = cy - 30
        s.line([(px, gy), (gx, gy)])
        s.text(px + side * 6, gy - 6, name, 11, "start" if side > 0 else "end")
        s.dot(gx, gy)
        s.res_v(gx, 62, gy, "Rсм", side=-side)
        s.tag_up(gx, 62, "Uсм")
        dx = gx + side * 34
        s.line([(gx, 76), (dx, 76)], PROP, dash=True)
        s.line([(gx, gy - 12), (dx, gy - 12)], PROP, dash=True)
        diode_up(s, dx, 76, gy - 12, "", PROP)
        s.text(dx + side * 12, 112, "½ 6Х7Б", 10, "start" if side > 0 else "end", PROP)
        s.text(dx + side * 12, 125, "(если нужен)", 10, "start" if side > 0 else "end", PROP)
        s.cap_h(min(gx, kx), max(gx, kx), gy, "Cп")
        s.dot(kx, gy)
        s.res_v(kx, 62, gy, "Ra 10k", side=-side)
        s.tag_up(kx, 62, "S")
        # ключ — на плате счётчика (спецплата в блоке счётчика); Cп, Rсм — на плате декатрона
        fx = kx - 70 if side < 0 else kx - 60
        s.rect(fx, 40, 110, 165, NOTE, dash=True, width=1)
        s.text(fx + 55, 222, "плата счётчика", 10, "middle", NOTE, italic=True)
        g1, g3 = s.pentode(kx, gy + 48, grid_side=side, grid_len=18)
        s.text(kx - side * 24, gy + 84, "GUIDE_EN_J2", 10, "middle")
        s.line([(kx, gy), (kx, gy + 28)])
        s.text(g1[0] + side * 4, g1[1] + 1, bus, 11, "start" if side > 0 else "end")
        s.text(g3[0] + side * 4, g3[1] + 9, "En", 11, "start" if side > 0 else "end")
        s.line([(kx, gy + 68), (kx, gy + 76)])
        s.tag_down(kx, gy + 76, "")
        s.text(kx + side * 14, gy + 80, "0 В", 10, "start" if side > 0 else "end")


# ---------------------------------------------------------------------------
def fig_write(out):
    W, H = 1200, 900
    s = Svg(W, H, "Декада с записью: 10 каналов записи")
    cx, cy, r = 570, 225, 66
    s.text(20, 26, "Рис. 1. Декада с записью (счётчик данных): канал записи в каждом катоде",
           15, bold=True)
    anode_and_guides(s, cx, cy, r)
    s.dekatron(cx, cy, r)

    x0, dx = 120, 100
    yK, yB, yT, yE = 400, 520, 590, 650
    for i in range(10):
        x = x0 + i * dx
        px, py = cathode_pin(cx, cy, r, i)
        s.line([(px, py), (px, py + 8 + abs(i - 4.5) * 4), (x, 330), (x, yK)])
        s.dot(x, yK)
        s.text(x + 6, yK - 6, f"K{i}", 11)
        read_tap(s, x, yK, i)
        s.res_v(x, yK, yB, "Rк 33k" if i == 0 else "", side=1)
        s.dot(x, yB)
        s.text(x - 6, yB - 6, f"B{i}", 11, "end")
        # подтяжка узла записи — на плате счётчика (каналы записи)
        s.line([(x, yB + 14), (x + 30, yB + 14)])
        s.dot(x, yB + 14)
        s.res_v(x + 30, yB + 14, yB + 56, "Rп 62k" if i == 0 else "")
        s.tag_down(x + 30, yB + 56, "+150" if i == 0 else "")
        gx, gy = s.triode(x, yT, grid_side=-1, grid_len=6)
        s.line([(x, yB), (x, yT - 18)])
        s.dot(gx, gy)
        s.cap_h(gx - 30, gx, gy)
        s.text(gx - 34, gy + 4, f"W{i}", 10, "end")
        s.res_v(gx, gy, yE, "", side=-1)
        s.dot(gx, yE)
        s.line([(x, yT + 18), (x, yE)])
        s.dot(x, yE)
    s.line([(x0 - 30, yE), (x0 + 9 * dx + 30, yE)], width=2.5)
    s.text(x0 + 9 * dx + 36, yE + 4, "−Eк −50 В", 13, bold=True)
    s.text(x0 - 30, yE + 22, "каналы записи: 10 триодов = 5 × 6Н16Б; Cс 100 пФ, Rс 1M к катоду", 12)
    board_split(s, 20, 1180, yB - 22, "плата декатрона", "плата счётчика: каналы записи")
    s.text(1180, yB + 30, "(через разъём: B0…B9)", 10, "end", NOTE, italic=True)

    # пояснения
    y = 720
    rows = [
        "чт0…чт9 — узлы сеток вентилей: диод ½ 6Х7Б к линии, подтяжка 100k к +5 В; дальше BinToBcdN "
        "(активный ноль) и признаки Zero/Nine.",
        "Чтение: Bi ≈ −20 В. Не горит: Ki ≈ −15 В, диод открыт, сетка ≈ −12…−15 В — «0». "
        "Горит: Ki ≈ +3…+7 В, диод заперт, сетка ≈ −0,7 В — «1».",
        "Запись: Wi падает (ВВ +150 → +50), через Cс сетка уходит на 100 В ниже катода: "
        "лампа закрыта на τ = Rс·Cс ≈ 100 мкс.",
        "Закрытые узлы поднимаются через Rп к +150 В (диоды заперты, стока с линии нет): "
        "разряду остаётся единственный открытый катод.",
        "Подъём подкатодов: шина S ключей +50 В, при записи и сбросе +150 В (GLIFT_N16, "
        "один на счётчик); импульс идёт на подкатод через Cп 220 пФ.",
        "Смещение подкатодов Uсм ≈ 12…13 В через Rсм 100k (SPICE, §9.8); пунктир — "
        "восстанавливающий диод, если расчёт его потребует.",
    ]
    for k, t in enumerate(rows):
        s.text(20, y + 20 * k, t, 12)
    s.save(os.path.join(out, "dek_a110_write.svg"))


# ---------------------------------------------------------------------------
def fig_reset(out):
    W, H = 1160, 800
    s = Svg(W, H, "Декады только со сбросом")
    s.text(20, 26, "Рис. 2. Декады только со сбросом: каналы записи на K0 и на общей шине",
           15, bold=True)

    def panel(ox, title, singles, note):
        cx, cy, r = ox + 250, 200, 56
        s.text(ox + 10, 56, title, 13, bold=True)
        s.tag_up(cx, 88, "+350 В")
        s.res_v(cx, 88, cy - r, "Rа")
        s.dekatron(cx, cy, r)
        x0, dx = ox + 40, 48
        yK, yR, yBus, yT, yE = 330, 400, 440, 560, 620
        common = [i for i in range(10) if i not in singles]
        bus_x = [x0 + i * dx for i in common]
        for i in range(10):
            x = x0 + i * dx
            px, py = cathode_pin(cx, cy, r, i)
            s.line([(px, py), (px, py + 8), (x, 300), (x, yK)])
            s.dot(x, yK)
            s.text(x + 4, yK - 6, f"K{i}", 10)
            # диод чтения (½ 6Х7Б): катод к линии, анод к узлу сетки
            diode_h(s, x - 22, x, yK - 0)
            s.res_v(x, yK, yR + 20, "", side=1)
            if i in singles:
                s.line([(x, yR + 20), (x, yT - 18)])
                s.triode(x, yT, grid_side=-1, grid_len=8)
                s.text(x - 2, yT + 34, f"V{i}", 10, "middle")
                s.line([(x, yT + 18), (x, yE)])
                s.dot(x, yE)
            else:
                s.line([(x, yR + 20), (x, yBus)])
                s.dot(x, yBus)
        s.text(x0 - 26, yK + 4, "чт", 10, "end")
        board_split(s, ox + 10, ox + 560, yBus + 26, "плата декатрона (перемычки: шина)",
                    "плата счётчика: каналы записи")
        # общая шина и её лампа
        bx1, bx2 = min(bus_x), max(bus_x)
        s.line([(bx1, yBus), (bx2, yBus)], width=2.5)
        xc = (bx1 + bx2) / 2
        s.text(bx2 + 6, yBus - 6, "Bобщ", 11)
        s.line([(xc, yBus), (xc, yT - 18)])
        s.triode(xc, yT, grid_side=1, grid_len=8)
        s.text(xc, yT + 34, "Vобщ", 10, "middle")
        s.line([(xc, yT + 18), (xc, yE)])
        s.dot(xc, yE)
        s.line([(xc, yBus + 52), (xc + 40, yBus + 52)])
        s.dot(xc, yBus + 52)
        s.res_v(xc + 40, yBus + 52, yBus + 100, "Rп")
        s.tag_down(xc + 40, yBus + 100, "+150")
        s.line([(x0 - 20, yE), (x0 + 9 * dx + 20, yE)], width=2.5)
        s.text(x0 + 9 * dx + 24, yE + 4, "−Eк", 12, bold=True)
        for k, t in enumerate(note):
            s.text(ox + 10, yE + 40 + 18 * k, t, 12)

    panel(10, "а) только в 0 (Loop, AP, IP-декады 0–1)", [0],
          ["Сброс в 0: закрыть Vобщ.",
           "V0 нужна для сброса; в обычном режиме с Vобщ",
           "выравнивает уровни на Rк (владелец).",
           "2 канала = 1 × 6Н16Б на декаду.",
           "Диоды чтения: AP, IP — все 10 линий;",
           "Loop — только K0 и K9 (Zero/Nine)."])
    panel(580, "б) в 0 и в 9 (IP-декады 2–4: 99900)", [0, 9],
          ["soft_rst → 0: закрыть Vобщ и V9.",
           "hard_rst → 9: закрыть Vобщ и V0.",
           "3 канала = 1,5 × 6Н16Б на декаду.",
           "Диоды чтения — на все 10 линий (IP читается)."])
    s.text(20, H - 20, "Подтяжка узлов сеток (100k к +5 В), Cс / Rс сеток V, −Eк и цепи подкатодов — как на рис. 1; "
           "здесь не показаны.", 12, NOTE)
    s.save(os.path.join(out, "dek_a110_reset.svg"))


# ---------------------------------------------------------------------------
def fig_board(out):
    """Структурная схема: плата декатрона и соседние платы (TRS v0.38–v0.40)."""
    W, H = 1200, 700
    s = Svg(W, H, "Плата декатрона: структурная схема")
    s.text(20, 26, "Рис. 0. Плата декатрона и соседние платы (одна плата — один декатрон)", 15, bold=True)

    def blk(x, y, w, h, title, lines, dash=False, color=INK, size=12):
        s.rect(x, y, w, h, color, dash=dash, fill="#fafafa" if not dash else "none")
        s.text(x + w / 2, y + 20, title, 13, "middle", color, bold=True)
        for k, t in enumerate(lines):
            s.text(x + w / 2, y + 40 + 17 * k, t, size - 1, "middle", color)

    def arrow(x1, y1, x2, y2, label="", up=True, color=INK, both=False):
        s.line([(x1, y1), (x2, y2)], color)
        ang = math.atan2(y2 - y1, x2 - x1)
        for (xa, ya, a) in ([(x2, y2, ang)] + ([(x1, y1, ang + math.pi)] if both else [])):
            p1 = (xa - 9 * math.cos(a - 0.4), ya - 9 * math.sin(a - 0.4))
            p2 = (xa - 9 * math.cos(a + 0.4), ya - 9 * math.sin(a + 0.4))
            s.line([p1, (xa, ya), p2], color)
        if label:
            s.text((x1 + x2) / 2, (y1 + y2) / 2 - 6 if up else (y1 + y2) / 2 + 15, label, 11,
                   "middle", color)

    # плата декатрона
    s.rect(20, 50, 700, 560, NOTE, dash=True, width=1.2)
    s.text(30, 70, "Плата декатрона: А110 (2 места) + обвязка ≤ 14 мест", 13, color=NOTE, bold=True)
    blk(50, 90, 200, 110, "А110 + Rа", ["декатрон, 13 выводов", "Rа 200k на плате", "(REQ-PR-020)"])
    blk(50, 240, 200, 120, "Rк × 10", ["33k на катод", "перемычки: запись /", "сброс 0 / сброс 0–9",
                                       "(общая шина Bобщ)"])
    blk(290, 90, 200, 110, "Цепи подкатодов", ["Cп 220 пФ × 2", "Rсм 100k × 2 → Uсм",
                                                "[½ 6Х7Б × 2, если нужен]"])
    blk(290, 240, 200, 120, "Диоды чтения", ["5 × 6Х7Б (10 линий)", "подтяжка 100k → +5 В",
                                             "развязка линий", "на время записи"])
    blk(520, 240, 180, 120, "BinToBcdN", ["≈ 7,5 ламп", "4 × ИЛИ-НЕ", "выход — активный ноль",
                                          "(TC-O3)"])
    blk(520, 400, 180, 90, "Буфер признаков", ["½ 6Н16Б на линию,", "если понадобится"], dash=True)
    s.text(370, 560, "Обвязка: 5 (6Х7Б) + 7,5 (BinToBcdN) = 12,5 из 14 мест; +1 — буфер Zero/Nine",
           12, "middle", NOTE)
    s.text(370, 580, "Питание: +350 В (анод), +150 / −50 В (вентили), +5 В, Uсм, накал 6,3 В", 12,
           "middle", NOTE)

    # связи внутри платы
    arrow(150, 200, 150, 240, "K0…K9", up=False)
    arrow(250, 300, 290, 300, "K")
    arrow(490, 300, 520, 300, "")
    s.text(505, 290, "чт", 11, "middle")
    arrow(250, 145, 290, 145, "ПК1, ПК2", both=True)
    s.line([(390, 360), (390, 445)])
    arrow(390, 445, 520, 445)
    s.text(395, 420, "K0, K9, TOP", 11)

    # разъём
    s.rect(740, 80, 40, 510, INK, fill="#eee")
    s.text(760, 72, "HD-68", 12, "middle", bold=True)
    sig = [(120, "Uп1, Uп2 ← ключи", 145), (300, "B0…B9 → каналы записи", 330),
           (300, "Out_n[3:0]", 300), (445, "Zero, Nine, TopPin", 445)]
    arrow(490, 145, 740, 145, "анод ключа → Cп", both=True)
    s.line([(150, 360), (150, 378)])
    arrow(150, 378, 740, 378, "B0…B9 (низ Rк) → каналы записи", both=True)
    arrow(700, 290, 740, 290, "")
    s.text(705, 280, "Out_n", 11)
    arrow(700, 445, 740, 445, "")

    # соседние платы: спецплата счётчика (1–2 на счётчик, в блоке своего счётчика)
    blk(830, 80, 350, 330, "Плата счётчика (1–2 на счётчик)",
        ["стоит в блоке своего счётчика:", "IP, Loop — IpLine; AP, Data — ApLine", "",
         "ключи подкатодов GUIDE_EN_J2:", "2 × 6Ж2Б на декаду, Ra 10k → шина S",
         "каналы записи WRCH_N16: ½ 6Н16Б,", "Rп 62k → +150 В, Cс 100 пФ, Rс 1M, −Eк",
         "повторитель шины S GLIFT_N16:", "+50 / +150 В при записи, 1 на счётчик", ""])
    rows = [("", "6Ж2Б", "6Н16Б", "плат"), ("IP", "10", "7+1", "2"), ("Loop", "4", "2+1", "1"),
            ("AP", "10", "5+1", "1–2"), ("Data", "6", "15+1", "2")]
    for k, row in enumerate(rows):
        for c, t in enumerate(row):
            s.text(880 + 75 * c, 300 + 18 * k, t, 11, "middle", bold=(k == 0))
    blk(830, 440, 350, 130, "Логика счётчика и память",
        ["Out_n → шины адреса / данных", "(активный ноль; память инвертирует сама)",
         "Zero, Nine → перенос (защёлки En)", "BcdToBinEn (запись) — вне платы"])
    arrow(780, 145, 830, 145, "", both=True)
    s.line([(780, 378), (805, 378), (805, 330)])
    arrow(805, 330, 830, 330, "")
    arrow(780, 300, 830, 480, "")
    arrow(780, 445, 830, 510, "")

    s.text(20, 640, "Узел B под Rк держит открытая лампа записи: кабель до платы счётчика висит на низкоомном "
           "узле. Катодная линия, диоды и BinToBcdN — рядом,", 12)
    s.text(20, 658, "без кабеля (SPICE §9.7–9.8). Ключ подкатода — на плате счётчика: кабель между анодом "
           "ключа и Cп (CKA 30 пФ в SPICE). 6Н16Б: каналы + GLIFT.", 12)
    s.save(os.path.join(out, "dek_a110_board.svg"))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        here, "..", "..", "sch", "logic", "DEKATRON_A110", "img")
    os.makedirs(out, exist_ok=True)
    fig_board(out)
    fig_write(out)
    fig_reset(out)


if __name__ == "__main__":
    main()
