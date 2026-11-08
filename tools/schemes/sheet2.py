"""Лист 2. Генератор фаз, формирователь импульсов, декатронный модуль."""
from lib import Fig


def fig_gates():
    f = Fig("gates", 1040, 356,
            "Вентильная схема: генератор фаз делит такт Clk на две фазы элементами задержки, "
            "формирователь на четырёх И и двух ИЛИ направляет фазы на подкатоды в порядке, "
            "заданном направлением шага.")
    f.dy = 16
    f.frame(70, 14, 520, 196, "DekatronPhaseGen — один на счётчик")
    f.frame(620, 14, 400, 250, "DekatronPulseSender — один на счётчик")

    # --- генератор фаз
    f.pin_in(12, 80, 90, "Clk")
    f.box(90, 55, 110, 50, "Impulse", ["фронт Clk"])
    f.wire([(200, 80), (240, 80)], arrow=False, label="ClkRise", lx=204, ly=73)
    f.wire([(240, 80), (240, 55), (270, 55)])
    f.box(270, 30, 130, 50, "OneShot", ["DELAY = PHASE1"])
    f.wire([(400, 55), (430, 55)], arrow=False, label="Win1", lx=404, ly=48)
    f.dot(430, 55)
    # вторая фаза запускается спадом первой: встык, без вентилей
    f.wire([(430, 55), (430, 96), (232, 96), (232, 145), (250, 145)])
    f.box(250, 120, 110, 50, "Impulse", ["по спаду, FALL=1"])
    f.wire([(360, 145), (430, 145)], label="Win1Fall", lx=364, ly=138)
    f.box(430, 120, 130, 50, "OneShot", ["DELAY = PHASE2"])
    f.text(330, 184, "Phase2 начинается спадом Phase1: зазора нет, нахлёст допустим", "tn", "middle")
    f.text(330, 200, "PHASE_DELAY_HS > 0: между ClkRise и Phase1 ещё OneShot + Impulse по спаду", "tn", "middle")

    # шины фаз
    f.wire([(430, 55), (640, 55)], "wacc", arrow=False, label="Phase1", lx=560, ly=48, lcls="tacc")
    f.dot(640, 55, "dot-acc")
    f.wire([(560, 145), (665, 145)], "wacc", arrow=False, label="Phase2", lx=576, ly=138, lcls="tacc")
    f.dot(665, 145, "dot-acc")
    f.wire([(640, 46), (640, 230)], "wacc", arrow=False)
    f.wire([(665, 106), (665, 170)], "wacc", arrow=False)

    # --- формирователь: шаги
    f.text(470, 294, "StepF", "tp", "end")
    f.wire([(476, 290), (690, 290), (690, 30)], arrow=False)
    f.text(470, 316, "StepR", "tp", "end")
    f.wire([(476, 312), (715, 312), (715, 150)], arrow=False)

    GX = 760
    rows = [(20, "fwdA", 690, 640), (80, "fwdB", 690, 665),
            (140, "revA", 715, 665), (200, "revB", 715, 640)]
    for y, name, s_bus, p_bus in rows:
        f.wire([(s_bus, y + 10), (GX, y + 10)])
        f.dot(s_bus, y + 10)
        cls = "wacc"
        f.wire([(p_bus, y + 26), (GX, y + 26)], cls)
        f.dot(p_bus, y + 26, "dot-acc")
        f.gate(GX, y, "&", name=name)

    OX = 880
    f.gate(OX, 60, "1")
    f.gate(OX, 140, "1")
    f.wire([(794, 38), (822, 38), (822, 70), (OX, 70)])        # fwdA
    f.wire([(794, 158), (834, 158), (834, 86), (OX, 86)])      # revA
    f.wire([(794, 98), (846, 98), (846, 150), (OX, 150)])      # fwdB
    f.wire([(794, 218), (858, 218), (858, 166), (OX, 166)])    # revB
    f.pin_out(914, 78, 950, "GuideA")
    f.pin_out(914, 158, 950, "GuideB")
    return f.render()


def fig_module():
    f = Fig("module", 1140, 470,
            "Декатронный модуль: ключи подкатодов на двух лампах J2, необязательная схема "
            "записи, каналы записи, декатрон, диоды чтения, необязательная схема чтения "
            "(активный ноль) и отводы позиций для схемы переноса.")
    # входы: общие шины подкатодов счётчика и разрешение декады
    for y, n in ((62, "GuideA"), (84, "GuideB"), (128, "En")):
        f.pin_in(12, y, 150, n)
    f.box(150, 44, 180, 100, "GUIDE_EN_J2 × 2",
          ["по лампе J2 на подкатод:", "пентод, 2 упр. сетки", "A = GuideA · En", "B = GuideB · En"])
    f.pin_in(12, 230, 150, "LineOpen[9:0]")
    f.box(150, 186, 180, 90, "Перемычки платы", ["WRITE: линия k → катод k", "сброс: K0 · общая шина",
                                                  "· K_TOP (TOP_LIMIT_MODE)", "выше MAX_DIGIT: 0"])
    f.text(240, 290, "1 — канал открыт; уровни строит счётчик", "tn", "middle")

    # каналы записи: счётные ячейки, выход — аналоговый узел B (в нетлисте открыт)
    f.box(150, 392, 260, 72, "WRCH_N16 × 10 / 3 / 2",
          ["½ 6Н16Б: канал записи по перемычкам", "выход — узел B, плата каналов записи",
           "катоды выше MAX_DIGIT без канала (TC-N1)"],
          cls="blk-opt", top=18)
    f.wire([(120, 230), (120, 420), (150, 420)], "w")
    f.dot(120, 230)
    f.text(126, 374, "LineOpen", "tn")

    # декатрон
    f.box(410, 44, 200, 330, "DekatronTube", [], top=24)
    f.lines(510, 140, ["V2 (такт) / Delay (синтез)", "кольцо из 30 электродов",
                       "LINES = катоды ≤ MAX_DIGIT"], "tm", "middle")
    f.wire([(330, 80), (410, 80)], "wacc", label="guide_a_i", lx=416, ly=84, lcls="tpi")
    f.wire([(330, 108), (410, 108)], "wacc", label="guide_b_i", lx=416, ly=112, lcls="tpi")
    f.wire([(330, 230), (410, 230)], label="line_open_i", lx=416, ly=234, lcls="tpi")
    f.text(604, 196, "катоды", "tpi", "end")

    # диоды чтения
    f.wire([(610, 210), (640, 210)])
    f.box(640, 170, 110, 96, "RDD_X7", ["½ 6Х7Б", "на линию:", "10 / K0·K9·TOP", "≤ MAX_DIGIT"], top=18)

    # выход и шина позиционного кода
    BX = 790
    f.wire([(750, 210), (BX, 210)], arrow=False)
    f.dot(BX, 210)
    f.wire([(BX, 82), (BX, 330)], "wbus", arrow=False)
    f.text(BX + 8, 360, "позиционный код [9:0]", "tn")
    f.wire([(BX, 82), (840, 82)])
    f.box(840, 52, 190, 60, "BinToBcdN", ["ИЛИ-НЕ по линиям 8-4-2-1"], cls="blk-opt")
    f.text(935, 126, "только при READ", "tn", "middle")
    f.pin_out(1030, 82, 1060, "Out_n[3:0]")
    for y, tap, name, opt in ((240, "[0]", "Zero", False), (272, "[9]", "Nine", False),
                              (304, "[TOP_PIN_OUT]", "TopPin", True)):
        f.wire([(BX, y), (1060, y)], "wd" if opt else "w")
        f.dot(BX, y)
        f.text(BX + 8, y - 5, tap, "tn")
        f.text(1066, y + 4, name, "tp")
    f.text(BX + 8, 324, "TopPin только при TOP_LIMIT_MODE", "tn")
    f.text(640, 420, "Out_n — тетрады активным нулём (TC-O3): память, терминал и эмулятор", "tn")
    f.text(640, 436, "принимают инверсный код; ячейки WRCH/RDD считают лампы модуля (TRS v0.40)", "tn")
    return f.render()
