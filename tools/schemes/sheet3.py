"""Лист 3. Декатронный счётчик DekatronCounter."""
from lib import Fig


def fig_counter():
    f = Fig("cnt", 1180, 670,
            "Декатронный счётчик на трёх декадах: разбор операции по Valid/Ready, окно записи, "
            "автомат, разводка линий установки и физических сбросов по декадам, общие генератор "
            "фаз и формирователь импульсов, цепочка разрешений декад на защёлкнутых признаках "
            "девятки и нуля.")
    # входы протокола
    for y, n in ((62, "valid"), (84, "dec"), (106, "set"), (128, "set_zero"), (150, "in[W-1:0]")):
        f.pin_in(12, y, 150, n)
    f.box(150, 40, 210, 130, "Разбор операции",
          ["accept = valid · ready", "set_any = set | set_zero |", "автопереходы предела",
           "step_f = accept·¬set_any·¬dec", "step_r = accept·¬set_any·dec"])

    # окно записи и автомат
    f.wire([(360, 70), (440, 70)], label="write_req", lx=368, ly=63)
    f.box(440, 40, 170, 60, "Окно записи", ["OneShot, WR_WINDOW_HS", "пуск: write_req | rst"])
    f.wire([(525, 100), (525, 130)], label="writing", lx=531, ly=120)
    f.wire([(360, 152), (440, 152)], label="accept, вид", lx=368, ly=145)
    f.box(440, 130, 170, 86, "Автомат", ["IDLE·SET·ZERO·TOP·RST", "ready = IDLE · ¬rst_active",
                                          "ZERO_ONLY: один busy_q"])

    # ready
    f.wire([(440, 195), (16, 195)], label="ready", lx=20, ly=188, lcls="tp")
    f.dot(260, 195)
    f.wire([(260, 195), (260, 170)])

    # линии установки и сбросы
    f.text(702, 16, "soft_rst", "tp", "middle")
    f.text(850, 16, "hard_rst", "tp", "middle")
    f.wire([(702, 22), (702, 40)])
    f.wire([(850, 22), (850, 40)])
    f.wire([(610, 170), (680, 170)], label="wr_*", lx=626, ly=163)
    f.box(680, 40, 240, 170, "Линии установки декад",
          ["wr_set  → SetData", "wr_zero → SetZero", "wr_top  → SetTop",
           "soft_rst → SetZero всех декад", "hard_rst → SetTop старших",
           "HARD_RST_D_CNT, SetZero прочих", "in держит мастер до ready"],
          align="start", bcls="tm")

    # генератор фаз и формирователь импульсов
    f.box(150, 250, 150, 60, "DekatronPhaseGen", ["один на счётчик"])
    f.wire([(300, 280), (350, 280)], label="Phase1·2", lx=304, ly=273)
    f.box(350, 240, 160, 70, "DekatronPulseSender", ["один на счётчик", "4 × И, 2 × ИЛИ"])
    f.wire([(345, 170), (345, 225), (430, 225), (430, 240)], "wacc", label="step_f · step_r",
           lx=352, ly=219, lcls="tacc")
    f.wire([(430, 310), (430, 340), (1010, 340)], "wbus", arrow=False)
    f.text(560, 333, "guide_a · guide_b", "tn")

    # шина установки
    f.wire([(800, 210), (800, 268)], "wbus", arrow=False)
    f.dot(800, 268)
    f.wire([(530, 268), (990, 268)], "wbus", arrow=False)
    f.text(820, 262, "SetData · SetZero · SetTop · in", "tn")

    D = [(400, "декада 0", "единицы"), (620, "декада 1", "десятки"), (840, "декада 2", "сотни")]
    for x, n1, n2 in D:
        f.box(x, 450, 160, 110, "DekatronModule", [n1 + " · " + n2, "ключ J2 подкатодов"], top=30)
        f.wire([(x + 90, 340), (x + 90, 450)])
        f.dot(x + 90, 340)
        f.wire([(x + 130, 268), (x + 130, 450)])
        f.dot(x + 130, 268)
        f.text(x + 24, 444, "En", "tn")

    # цепочка разрешений en_chain: младшая декада разрешена всегда
    f.wire([(380, 385), (575, 385)], "wacc", arrow=False)
    f.text(374, 389, "1", "tacc", "end")
    f.dot(420, 385, "dot-acc")
    f.wire([(420, 385), (420, 450)], "wacc")
    f.gate(575, 375, "&")
    f.wire([(567, 600), (567, 401), (575, 401)], "wacc")
    f.text(572, 436, "sel[0]", "tn")
    f.wire([(609, 393), (640, 393)], "wacc", arrow=False)
    f.dot(640, 393, "dot-acc")
    f.wire([(640, 393), (640, 450)], "wacc")
    f.wire([(640, 393), (795, 393)], "wacc", arrow=False)
    f.gate(795, 383, "&")
    f.wire([(787, 600), (787, 409), (795, 409)], "wacc")
    f.text(792, 436, "sel[1]", "tn")
    f.wire([(829, 401), (860, 401), (860, 450)], "wacc")
    f.text(150, 404, "sel[i] = dec ? zeroes_q[i]", "tl")
    f.text(150, 418, "         : nines_q[i]", "tl")

    # выходы декад
    f.wire([(540, 575), (1060, 575)], "wbus", arrow=False)
    for x, *_ in D:
        f.wire([(x + 140, 560), (x + 140, 575)], arrow=False)
        f.dot(x + 140, 575)
        f.wire([(x + 60, 560), (x + 60, 600)])
    f.text(1066, 579, "out", "tp")
    f.text(470, 590, "Zero · Nine · TopPin", "tn", "middle")

    # регистры состояния
    f.box(400, 600, 600, 50, "Регистры состояния",
          ["nines_q, zeroes_q [D−2:0] — перенос; zero_q · at_top_q — только TOP_LIMIT_MODE; без сброса"], top=19)
    f.pin_out(1000, 625, 1030, "zero, at_top ← катоды")
    f.wire([(400, 625), (130, 625), (130, 182), (170, 182), (170, 170)])
    f.text(136, 500, "zero_q · at_top_q", "tn")
    return f.render()


def fig_counter_fsm():
    f = Fig("cntfsm", 760, 390,
            "Автомат счётчика: шаг выполняется в состоянии IDLE без снятия ready, операции "
            "записи уходят в SET, ZERO или TOP на время окна записи, линии сброса — в RST "
            "до снятия линии и конца окна.")
    f.state("IDLE", 130, 145, "ST_IDLE", cls="st-acc")
    f.state("SET", 470, 55, "ST_SET")
    f.state("ZERO", 470, 145, "ST_ZERO")
    f.state("TOP", 470, 235, "ST_TOP")
    f.selfloop("IDLE", "t", "wacc", "шаг ±1, ready = 1", 130, 82)
    f.edge("IDLE", "r", "SET", "l", oa=-10, label="set", lx=300, ly=88)
    f.edge("IDLE", "r", "ZERO", "l", label="set_zero или TOP+1→0", lx=300, ly=139)
    f.edge("IDLE", "r", "TOP", "l", oa=10, label="0−1 → TOP_VALUE", lx=300, ly=240)
    for k in ("SET", "ZERO", "TOP"):
        cx, cy, w, h = f.states[k]
        f.wire([(cx + w / 2, cy), (640, cy)], arrow=False)
    f.wire([(640, 55), (640, 275), (130, 275), (130, 162)])
    f.text(646, 160, "writing", "tl")
    f.text(646, 174, "снят", "tl")
    f.text(380, 270, "окно записи закончилось", "tl", "middle")
    f.state("RST", 330, 315, "ST_RST")
    f.edge("RST", "l", "IDLE", "b", ob=-30, via=[(100, 315)],
           label="линия снята · окно истекло", lx=176, ly=309)
    f.selfloop("RST", "b", "w", "rst_active | writing", 330, 382)
    f.text(16, 24, "soft_rst | hard_rst → ST_RST из любого состояния, запуск окна записи; rst_n → ST_RST", "tl")
    f.text(16, 40, "ZERO_ONLY (без записи, предела и сброса в 9 — вложенность, AP): ZERO и RST слиты в busy_q, SET и TOP нет", "tl")
    return f.render()
