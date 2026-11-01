#!/usr/bin/env python3
"""Эскизы декатронного модуля А110 с катодными лампами записи.

Рисует три SVG для страницы sch/logic/DEKATRON_A110/README.md:
  dek_a110_write.svg  — декада с записью (счётчик данных): 10 катодных ламп;
  dek_a110_reset.svg  — декады только со сбросом: 2 (или 3) катодные лампы;

Это эскиз для обсуждения, не схема KiCad: номиналы — оценки.
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
        s.res_v(kx, 62, gy, "Ra", side=-side)
        s.tag_up(kx, 62, "+150")
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
    W, H = 1200, 810
    s = Svg(W, H, "Декада с записью: 10 катодных ламп")
    cx, cy, r = 570, 225, 66
    s.text(20, 26, "Рис. 1. Декада с записью (счётчик данных): лампа записи в каждом катоде",
           15, bold=True)
    anode_and_guides(s, cx, cy, r)
    s.dekatron(cx, cy, r)

    x0, dx = 120, 100
    yK, yB, yT, yE = 385, 495, 555, 615
    for i in range(10):
        x = x0 + i * dx
        px, py = cathode_pin(cx, cy, r, i)
        s.line([(px, py), (px, py + 8 + abs(i - 4.5) * 4), (x, 350), (x, yK)])
        s.dot(x, yK)
        s.text(x + 6, yK - 6, f"K{i}", 11)
        s.arrow_out(x, yK, f"чт{i}", side=-1)
        s.res_v(x, yK, yB, "Rк" if i == 0 else "", side=1)
        s.dot(x, yB)
        s.text(x - 6, yB - 6, f"B{i}", 11, "end")
        # подтяжка (предложение)
        s.line([(x, yB), (x + 30, yB)])
        s.res_v(x + 30, yK + 30, yB, "Rп" if i == 0 else "")
        s.tag_up(x + 30, yK + 30, "+150")
        gx, gy = s.triode(x, yT, grid_side=-1, grid_len=6)
        s.line([(x, yB), (x, yT - 18)])
        s.dot(gx, gy)
        s.cap_h(gx - 30, gx, gy)
        s.text(gx - 32, gy - 8, f"W{i}", 10, "end")
        s.res_v(gx, gy, yE, "", side=-1)
        s.dot(gx, yE)
        s.line([(x, yT + 18), (x, yE)])
        s.dot(x, yE)
    s.line([(x0 - 30, yE), (x0 + 9 * dx + 30, yE)], width=2.5)
    s.text(x0 + 9 * dx + 36, yE + 4, "−Eк", 13, bold=True)
    s.text(x0 + 9 * dx + 36, yE + 20, "(отрицательное", 11, color=NOTE)
    s.text(x0 + 9 * dx + 36, yE + 34, "смещение)", 11, color=NOTE)
    s.text(x0 - 30, yE + 22, "лампы записи V0…V9: 10 триодов = 5 × 6Н16Б", 12)

    # пояснения
    y = 670
    rows = [
        ("чт0…чт9 — линии чтения, уровень НВ: на BinToBcd (отдельная плата) и признаки Zero/Nine.", INK),
        ("Чтение: лампа открыта, Bi = −20 В. Не горит: Ki = −20 В — НВ «0». Горит: Ki ≈ 0 В "
         "(I·Rк > 20 В, сетки нагрузки зажимают) — НВ «1».", INK),
        ("Запись: Wi падает (ВВ +150 → +50), через Cс сетка уходит на 100 В ниже катода, "
         "лампа закрыта на τ = Rс·Cс ≫ такт.", INK),
        ("Bi и Ki закрытых катодов поднимаются через Rп к +150 В, разряду остаётся "
         "единственный открытый катод.", INK),
        ("Сброс в 0 / в TOP — та же запись с фиксированным номером.", INK),
        ("Подкатоды — по Яблонскому (рис. 3-1, 3-4, 4-8): импульс через Cп, "
         "смещение Uсм через Rсм; пунктир — восстанавливающий диод, если расчёт его потребует.", INK),
    ]
    for k, (t, c) in enumerate(rows):
        s.text(20, y + 20 * k, t, 12, c)
    s.save(os.path.join(out, "dek_a110_write.svg"))


# ---------------------------------------------------------------------------
def fig_reset(out):
    W, H = 1160, 760
    s = Svg(W, H, "Декады только со сбросом")
    s.text(20, 26, "Рис. 2. Декады только со сбросом: катодные лампы на нуле и на общей шине",
           15, bold=True)

    def panel(ox, title, singles, note):
        cx, cy, r = ox + 250, 200, 56
        s.text(ox + 10, 56, title, 13, bold=True)
        s.tag_up(cx, 88, "+350 В")
        s.res_v(cx, 88, cy - r, "Rа")
        s.dekatron(cx, cy, r)
        x0, dx = ox + 40, 48
        yK, yR, yBus, yT, yE = 330, 400, 440, 530, 590
        common = [i for i in range(10) if i not in singles]
        bus_x = [x0 + i * dx for i in common]
        for i in range(10):
            x = x0 + i * dx
            px, py = cathode_pin(cx, cy, r, i)
            s.line([(px, py), (px, py + 8), (x, 300), (x, yK)])
            s.dot(x, yK)
            s.text(x + 4, yK - 6, f"K{i}", 10)
            s.line([(x, yK), (x - 14, yK)])
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
        s.text(x0 - 18, yK + 4, "чт", 10, "end")
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
        s.line([(xc, yBus + 12), (xc + 40, yBus + 12)])
        s.dot(xc, yBus + 12)
        s.res_v(xc + 40, yBus + 12, yBus + 70, "Rп")
        s.tag_down(xc + 40, yBus + 70, "+150")
        s.line([(x0 - 20, yE), (x0 + 9 * dx + 20, yE)], width=2.5)
        s.text(x0 + 9 * dx + 24, yE + 4, "−Eк", 12, bold=True)
        for k, t in enumerate(note):
            s.text(ox + 10, yE + 40 + 18 * k, t, 12)

    panel(10, "а) только в 0 (Loop, AP, IP-декады 0–1)", [0],
          ["Сброс в 0: закрыть Vобщ.",
           "V0 всегда открыта: K0 на том же уровне,",
           "что и остальные, и в том же Rк·I.",
           "2 триода = 1 × 6Н16Б на декаду."])
    panel(580, "б) в 0 и в 9 (IP-декады 2–4: 99900)", [0, 9],
          ["soft_rst → 0: закрыть Vобщ и V9.",
           "hard_rst → 9: закрыть Vобщ и V0.",
           "3 триода = 1,5 × 6Н16Б на декаду."])
    s.text(20, H - 20, "Сетки V0, Vобщ, V9 — через Cс / Rс, цепи подкатодов — как на рис. 1; здесь не показаны.",
           12, NOTE)
    s.save(os.path.join(out, "dek_a110_reset.svg"))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        here, "..", "..", "sch", "logic", "DEKATRON_A110", "img")
    os.makedirs(out, exist_ok=True)
    fig_write(out)
    fig_reset(out)


if __name__ == "__main__":
    main()
