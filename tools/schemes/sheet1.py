"""Лист 1. Модель декатрона DekatronTubeV2."""
from lib import Fig, polar

CX, CY, R = 280, 272, 182


def idx_angle(i):
    return -90 + 12 * i


def arc(f, i1, i2, r, cls="wacc"):
    a1, a2 = idx_angle(i1), idx_angle(i2)
    d = 1.5 if a2 > a1 else -1.5
    x1, y1 = polar(CX, CY, r, a1 + d)
    x2, y2 = polar(CX, CY, r, a2 - d)
    sweep = 1 if a2 > a1 else 0
    f.path(f"M{x1:.1f},{y1:.1f} A{r},{r} 0 0 {sweep} {x2:.1f},{y2:.1f}", cls)


def fig_ring():
    f = Fig("ring", 560, 560,
            "Кольцо из 30 электродов декатрона: десять главных катодов и по два подкатода "
            "между ними. Показан шаг +1 с K3 на K4 через подкатоды A и B и неудачный шаг "
            "на K8, когда без второй фазы разряд падает назад.")
    # анод
    f.add(f'<circle cx="{CX}" cy="{CY}" r="54" class="anode"/>')
    f.text(CX, CY - 4, "анод", "tt", "middle")
    f.text(CX, CY + 13, "cathodes_q[29:0]", "tm", "middle")
    f.text(CX, CY + 27, "ровно один бит", "tl", "middle")

    for i in range(30):
        x, y = polar(CX, CY, R, idx_angle(i))
        if i % 3 == 0:
            d = i // 3
            if d == 3:
                f.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="22" class="halo"/>')
                f.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="13" class="lit"/>')
            else:
                f.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="13" class="kmain"/>')
            lx, ly = polar(CX, CY, R + 33, idx_angle(i))
            f.text(lx, ly + 4, f"K{d}", "tk", "middle")
            ix, iy = polar(CX, CY, R, idx_angle(i))
            f.text(ix, iy + 4, str(i), "ti", "middle")
        elif i % 3 == 1:
            f.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" class="kga"/>')
        else:
            f.add(f'<rect x="{x - 5.5:.1f}" y="{y - 5.5:.1f}" width="11" height="11" class="kgb"/>')

    # цель шага: K4
    tx, ty = polar(CX, CY, R, idx_angle(12))
    f.add(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="19" class="tgt"/>')

    # шаг +1: K3 (9) -> A (10) -> B (11) -> K4 (12)
    rr = R - 24
    arc(f, 9, 10, rr)
    arc(f, 10, 11, rr)
    arc(f, 11, 12, rr)
    for i, num in ((9.5, "1"), (10.5, "2"), (11.5, "3")):
        x, y = polar(CX, CY, rr - 15, idx_angle(i))
        f.text(x, y + 4, num, "tnum", "middle")
    f.text(374, 334, "шаг +1", "tacc", "end")
    f.text(374, 348, "K3 → K4", "tm", "end")

    # неудачный шаг: K8 (24) -> A (25) и падение назад
    arc(f, 24, 25, rr, "wd")
    arc(f, 25, 24, rr - 18, "wd")
    f.text(170, 256, "нет фазы 2:", "tl", "middle")
    f.text(170, 270, "падение назад", "tl", "middle")

    # легенда
    ly = 528
    f.add(f'<circle cx="34" cy="{ly - 4}" r="7" class="kmain"/>')
    f.text(48, ly, "главный катод K0…K9, индекс 3k", "tl")
    f.add(f'<circle cx="290" cy="{ly - 4}" r="5" class="kga"/>')
    f.text(302, ly, "подкатод A, 3k+1", "tl")
    f.add(f'<rect x="420" y="{ly - 9}" width="10" height="10" class="kgb"/>')
    f.text(436, ly, "подкатод B, 3k+2", "tl")
    return f.render()


def fig_tube():
    f = Fig("tube", 1140, 390,
            "Внутреннее устройство модели декатрона: выбор направления по подкатодным "
            "линиям и положению разряда, таймер перемещения, кольцевой регистр, узел "
            "записи и сброса, дешифратор главных катодов.")
    # входы
    f.pin_in(12, 82, 140, "guide_a_i")
    f.pin_in(12, 112, 140, "guide_b_i")
    f.pin_in(12, 262, 140, "write_en_i")
    f.pin_in(12, 286, 140, "write_pos_i[9:0]")
    f.pin_in(12, 310, 140, "reset0_i")
    f.pin_in(12, 334, 140, "resetN_i")

    f.box(140, 44, 180, 112, "Выбор направления",
          ["A — к ближайшему 3k+1", "B — к ближайшему 3k+2", "нет — падение на катод",
           "оба сразу — стоим"])
    f.box(140, 238, 180, 118, "Запись и сброс",
          ["цель: K(pos), K0, K(N)", "wr_timer ≥ MIN", "→ один раз загрузить цель",
           "смена цели = новая", "операция"])

    f.wire([(320, 100), (380, 100)], label="±1", lx=340, ly=92)
    f.box(380, 44, 180, 112, "Таймер перемещения",
          ["move_timer ≥ move_time", "GUIDE_STEP_HS при", "активном подкатоде,",
           "FALL_STEP_HS при падении"])
    f.wire([(560, 100), (620, 100)], "wacc", label="сдвиг", lx=568, ly=92, lcls="tacc")
    f.box(620, 44, 180, 112, "Кольцо cathodes_q",
          ["[29:0], один бит", "rot_fwd: idx+1", "rot_back: idx−1"], cls="blk-acc")

    # обратная связь: класс положения
    f.wire([(660, 156), (660, 194), (230, 194), (230, 156)],
           label="класс положения: катод / A / B", lx=445, ly=188, anchor="middle")
    # запись блокирует перемещение
    f.wire([(190, 238), (190, 156)], label="перемещения нет", lx=196, ly=222)
    # загрузка цели
    f.wire([(320, 298), (740, 298), (740, 156)], label="загрузка цели в кольцо", lx=470, ly=290,
           anchor="middle")

    # дешифратор
    f.wire([(800, 100), (850, 100)])
    f.box(850, 44, 160, 112, "Дешифратор",
          ["main = cathodes[3d]", "выход только если", "разряд на катоде и", "воздействий нет"])
    f.pin_out(1010, 100, 1022, "")
    f.text(1016, 92, "main_onehot_o", "tp", "start")

    # отладочные выходы
    f.wire([(800, 135), (825, 135), (825, 286), (850, 286)])
    f.box(850, 238, 200, 118, "Отладка", ["cathodes_dbg_o[29:0]", "on_guide · moving",
                                           "in_write_reset · settled", "invalid"],
          cls="blk-opt")
    f.text(140, 380, "Все регистры тактируются hsClk; цифровых сбросов у модели нет — "
                     "только катодные импульсы reset0_i и resetN_i.", "tl")
    return f.render()


def fig_timing():
    # время в тактах hsClk от −1 до 11; такт Clk = 10 hsClk
    X0, SC = 210, 52

    def X(t):
        return X0 + SC * (t + 1)

    rows = [("hsClk", 46), ("Clk", 84), ("Phase1", 122), ("Phase2", 160),
            ("GuideA", 198), ("GuideB", 236), ("разряд", 284), ("main_onehot_o", 350)]
    f = Fig("tim", 900, 378,
            "Временная диаграмма инкремента за один такт счёта: первая треть такта — "
            "подкатод A, вторая — подкатод B, третья — падение разряда на следующий "
            "главный катод.")
    for name, y in rows:
        f.text(16, y + 4, name, "tp")
    H = 24

    def wave(y, segs, cls="wv"):
        # segs: список (t_from, t_to, level)
        pts = []
        for a, b, lv in segs:
            yy = y - H / 2 if lv else y + H / 2
            pts += [(X(a), yy), (X(b), yy)]
        f.wire(pts, cls, arrow=False)

    # сетка тактов hsClk
    for t in range(-1, 12):
        f.add(f'<line x1="{X(t)}" y1="30" x2="{X(t)}" y2="364" class="grid"/>')
        if t >= 0:
            f.text(X(t), 50, str(t), "ti", "middle")
    # фазы такта
    for a, b, name in ((0, 3, "PHASE1_HS = 3"), (3, 6, "PHASE2_HS = 3"), (6, 10, "падение 3 + запас 1")):
        f.text((X(a) + X(b)) / 2, 22, name, "tl", "middle")
        f.wire([(X(a) + 2, 27), (X(b) - 2, 27)], "wthin", arrow=False)

    wave(84, [(-1, 0, 0), (0, 5, 1), (5, 10, 0), (10, 11, 1)])
    wave(122, [(-1, 0, 0), (0, 3, 1), (3, 10, 0), (10, 11, 1)])
    wave(160, [(-1, 3, 0), (3, 6, 1), (6, 11, 0)])
    wave(198, [(-1, 0, 0), (0, 3, 1), (3, 10, 0), (10, 11, 1)], "wvacc")
    wave(236, [(-1, 3, 0), (3, 6, 1), (6, 11, 0)], "wvacc")

    # шина положения разряда
    def bus(y, segs, cls="bus"):
        for a, b, lab, c in segs:
            x1, x2 = X(a), X(b)
            f.add(f'<polygon points="{x1 + 4},{y - 11} {x2 - 4},{y - 11} {x2},{y} {x2 - 4},{y + 11} '
                  f'{x1 + 4},{y + 11} {x1},{y}" class="{c}"/>')
            f.text((x1 + x2) / 2, y + 4, lab, "tm", "middle")

    bus(284, [(-1, 2, "K3", "seg"), (2, 5, "A (10)", "seg-acc"), (5, 9, "B (11)", "seg-acc"),
              (9, 11, "K4", "seg")])
    bus(350, [(-1, 0, "K3", "seg"), (0, 9, "нулевой код: разряд в пути", "seg-off"),
              (9, 11, "K4", "seg")])
    # размерные пометки
    for a, b, lab in ((0, 2, "GUIDE_STEP"), (3, 5, "GUIDE_STEP"), (6, 9, "FALL_STEP")):
        f.wire([(X(a), 304), (X(b), 304)], "wthin", arrow=True, start_arrow=True)
        f.text((X(a) + X(b)) / 2, 316, lab, "tn", "middle")
    return f.render()
