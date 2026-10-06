"""Лист 2. Генератор фаз, формирователь импульсов, декатронный модуль."""
from lib import Fig


def fig_gates():
    f = Fig("gates", 1040, 356,
            "Вентильная схема: генератор фаз делит такт Clk на две фазы элементами задержки, "
            "формирователь на четырёх И и двух ИЛИ направляет фазы на подкатоды в порядке, "
            "заданном направлением шага.")
    f.dy = 16
    f.frame(70, 14, 520, 196, "DekatronPhaseGen — один на счётчик")
    f.frame(620, 14, 400, 250, "DekatronPulseSender — в каждой декаде")

    # --- генератор фаз
    f.pin_in(12, 80, 90, "Clk")
    f.box(90, 55, 110, 50, "Impulse", ["фронт по hsClk"])
    f.wire([(200, 80), (240, 80)], arrow=False, label="ClkRise", lx=204, ly=73)
    f.dot(240, 80)
    f.wire([(240, 80), (240, 55), (270, 55)])
    f.wire([(240, 80), (240, 145), (270, 145)])
    f.box(270, 30, 130, 50, "OneShot", ["DELAY = PHASE1"])
    f.box(270, 120, 130, 50, "OneShot", ["DELAY = PHASE1+2"])
    f.wire([(400, 55), (430, 55)], arrow=False, label="Win1", lx=404, ly=48)
    f.dot(430, 55)
    f.wire([(430, 55), (430, 91), (450, 91)])
    f.gate(450, 78, "1", w=30, h=26, inv=True)
    f.wire([(488, 91), (500, 91), (500, 120), (520, 120)])
    f.wire([(400, 145), (510, 145), (510, 136), (520, 136)], label="Win12", lx=404, ly=161)
    f.gate(520, 110, "&")
    f.text(537, 168, "Phase2 = Win12·¬Win1", "tn", "middle")

    # шины фаз
    f.wire([(430, 55), (640, 55)], "wacc", arrow=False, label="Phase1", lx=560, ly=48, lcls="tacc")
    f.dot(640, 55, "dot-acc")
    f.wire([(554, 128), (665, 128)], "wacc", arrow=False, label="Phase2", lx=570, ly=121, lcls="tacc")
    f.dot(665, 128, "dot-acc")
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
    f = Fig("module", 1060, 420,
            "Декатронный модуль: формирователь импульсов, необязательная схема записи, "
            "декатрон, необязательная схема чтения, признак достоверности показания и "
            "отводы позиций для схемы переноса.")
    # входы
    for y, n in ((62, "StepF"), (84, "StepR"), (106, "Phase1_i"), (128, "Phase2_i")):
        f.pin_in(12, y, 150, n)
    f.box(150, 44, 180, 100, "DekatronPulseSender",
          ["4 × И, 2 × ИЛИ", "EXT_PHASES = 0:", "свой генератор фаз"])
    f.pin_in(12, 206, 150, "In[3:0]")
    f.pin_in(12, 230, 150, "SetData")
    f.box(150, 186, 180, 70, "BcdToBinEn", ["BCD → позиционный код", "10 × И, 5-й вход = SetData"],
          cls="blk-opt")
    f.text(240, 270, "только при WRITE", "tn", "middle")
    f.pin_in(12, 300, 410, "SetZero")
    f.pin_in(12, 344, 150, "SetTop")
    f.box(150, 328, 180, 32, None, [], cls="blk-opt")
    f.text(240, 349, "только TOP_LIMIT_MODE", "tn", "middle")
    f.wire([(330, 344), (410, 344)])

    # декатрон
    f.box(410, 44, 200, 330, "DekatronTubeV2", [], top=24)
    f.lines(500, 140, ["кольцо из 30 электродов", "RESET_N_POS = TOP_PIN_OUT"], "tm", "middle")
    f.wire([(330, 80), (410, 80)], "wacc", label="guide_a_i", lx=416, ly=84, lcls="tpi")
    f.wire([(330, 108), (410, 108)], "wacc", label="guide_b_i", lx=416, ly=112, lcls="tpi")
    f.wire([(330, 210), (410, 210)], label="write_pos_i", lx=416, ly=214, lcls="tpi")
    f.wire([(330, 232), (410, 232)], label="write_en_i", lx=416, ly=236, lcls="tpi")
    f.text(416, 304, "reset0_i", "tpi")
    f.text(416, 348, "resetN_i", "tpi")
    f.text(604, 196, "main_onehot_o", "tpi", "end")

    # выход и шина позиционного кода
    BX = 690
    f.wire([(610, 210), (BX, 210)], arrow=False)
    f.dot(BX, 210)
    f.wire([(BX, 82), (BX, 330)], "wbus", arrow=False)
    f.text(BX + 8, 360, "позиционный код [9:0]", "tn")
    f.wire([(BX, 82), (740, 82)])
    f.box(740, 52, 170, 60, "BinToBcd", ["ИЛИ по линиям 8-4-2-1"], cls="blk-opt")
    f.text(825, 126, "только при READ", "tn", "middle")
    f.pin_out(910, 82, 940, "Out[3:0]")
    for y, tap, name, opt in ((240, "[0]", "Zero", False), (272, "[9]", "Nine", False),
                              (304, "[TOP_PIN_OUT]", "TopPin", True)):
        f.wire([(BX, y), (940, y)], "wd" if opt else "w")
        f.dot(BX, y)
        f.text(BX + 8, y - 5, tap, "tn")
        f.text(946, y + 4, name, "tp")
    f.text(BX + 8, 324, "TopPin только при TOP_LIMIT_MODE", "tn")
    return f.render()
