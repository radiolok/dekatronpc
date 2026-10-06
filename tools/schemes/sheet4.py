"""Лист 4. Линия выборки инструкций IpLine."""
from lib import Fig


def fig_ipline():
    f = Fig("ipl", 1200, 470,
            "Линия выборки: автомат управляет счётчиком инструкций и счётчиком вложенности "
            "циклов, читает опкоды из памяти программ в регистр инструкции и по детектору "
            "скобок решает, нужна ли промотка тела цикла.")
    pins_in = [(62, "valid, op[1:0]"), (88, "loop_val_zero"), (148, "halt_rq, key_±ip"),
               (196, "insn_loading, mode"), (218, "insn_in, valid")]
    for y, n in pins_in:
        f.pin_in(12, y, 200, n)
    f.wire([(200, 118), (16, 118)], label="ready", lx=20, ly=111, lcls="tp")
    f.wire([(200, 244), (16, 244)], label="insn_in_ready", lx=20, ly=237, lcls="tp")
    f.wire([(200, 272), (16, 272)], label="loop_overflow", lx=20, ly=265, lcls="tp")

    f.box(200, 40, 220, 250, "Автомат выборки",
          ["ip_counted_q — IP уже", "сдвинут под инструкцию", "",
           "scanning_q, scan_dec_q —", "идёт промотка, куда", "",
           "loop_init_q — шаг на своей", "скобке", "",
           "overflow_q — глубина > 99"], align="start", top=22)

    # счётчик инструкций
    f.wire([(420, 70), (560, 70)], label="valid · dec", lx=428, ly=63)
    f.wire([(560, 108), (420, 108)], label="ready · out_valid", lx=428, ly=101)
    f.box(560, 40, 210, 100, "DekatronCounter · IP",
          ["5 декад, 0…99999", "HARD_RST_D_CNT = 3", "hard_rst → 99900", "soft_rst → 00000"])

    # счётчик циклов
    f.wire([(420, 186), (560, 186)], label="valid · dec · set_zero", lx=428, ly=179)
    f.wire([(560, 224), (420, 224)], label="zero · out_valid", lx=428, ly=217)
    f.box(560, 168, 210, 80, "DekatronCounter · Loop",
          ["TRS: 2 декады, 0…99", "RTL: 3 декады (parameters.sv)", "переход через 0 = переполнение"])

    # память программ
    f.wire([(770, 90), (880, 90)], label="ip_addr (BCD)", lx=778, ly=83)
    f.box(880, 40, 250, 210, "IpMemory",
          ["Ram 100 000 × 4 бит", "банки 100×100", "", "старший банк 999xx —",
           "ПЗУ загрузчика", "(наложение ovl_*)", "", "запись туда → err",
           "rd_data — регистр"])
    f.wire([(310, 40), (310, 20), (1005, 20), (1005, 40)],
           label="mem_valid · mem_wr · wr_data", lx=658, ly=14, anchor="middle")

    # регистр инструкции и детектор
    f.wire([(1005, 250), (1005, 340), (770, 340)], "wacc",
           label="rd_data · rd_valid", lx=1012, ly=300, lcls="tacc")
    f.box(560, 310, 210, 80, "insn_q + InsnLoopDetector",
          ["0x6 — [ или {", "0x7 — ] или }", "один детектор на регистр"])
    f.wire([(560, 340), (310, 340), (310, 290)], "wacc",
           label="скобка открыта / закрыта", lx=316, ly=334)
    f.wire([(665, 390), (665, 430), (16, 430)], label="insn, insn_valid", lx=20, ly=423,
           lcls="tp")
    f.text(16, 456, "Опкоды на этом уровне — только 4-битные коды; символы преобразует "
                    "загрузчик программ.", "tl")
    return f.render()


def fig_ipline_fsm():
    f = Fig("iplfsm", 1100, 440,
            "Автомат IpLine. Основной цикл: шаг IP, ожидание установления адреса, чтение "
            "опкода. Ветвь промотки: разбор скобки, шаг счётчика вложенности, снова шаг IP "
            "до парной скобки.")
    f.state("HALT", 110, 60, "S_HALT")
    f.state("IDLE", 400, 60, "S_IDLE", cls="st-acc")
    f.state("FETCH", 700, 60, "S_FETCH")
    f.state("SCAN", 960, 60, "S_SCAN_EVAL")
    f.state("INSN_IN", 110, 210, "S_INSN_IN")
    f.state("IP_OP", 400, 210, "S_IP_OP")
    f.state("IP_WAIT", 700, 210, "S_IP_WAIT")
    f.state("LOOP_OP", 960, 210, "S_LOOP_OP")
    f.state("WRITE", 110, 360, "S_WRITE")
    f.state("LOOP_WAIT", 960, 360, "S_LOOP_WAIT")

    # останов
    f.edge("HALT", "r", "IDLE", "l", oa=-8, ob=-8, label="halt_rq снят", lx=255, ly=45)
    f.edge("IDLE", "l", "HALT", "r", oa=8, ob=8, label="halt_rq, IP не сдвинут", lx=255, ly=86)
    f.edge("HALT", "b", "IP_OP", "l", oa=20, ob=-10, via=[(130, 160), (280, 160), (280, 200)],
           label="кнопка ±IP", lx=205, ly=176)

    # из IDLE вниз
    f.edge("IDLE", "b", "INSN_IN", "t", oa=-35, ob=-30, via=[(365, 120), (80, 120)],
           label="загрузка с текущего адреса", lx=220, ly=114)
    f.edge("IDLE", "b", "IP_OP", "t", oa=-15, ob=-15, cls="wwarn", label="останов: IP+1",
           lx=378, ly=178, anchor="end", lcls="twarn")
    f.edge("IDLE", "b", "IP_OP", "t", oa=10, ob=10, label="шаг IP", lx=418, ly=170,
           anchor="start")
    f.edge("IDLE", "b", "LOOP_OP", "r", oa=35, via=[(435, 110), (1040, 110), (1040, 210)],
           label="текущая скобка требует промотки", lx=560, ly=104)

    # основной цикл
    f.edge("IDLE", "r", "FETCH", "l", oa=-8, ob=-8, label="IP не сдвинут: чтение на месте",
           lx=550, ly=45)
    f.edge("FETCH", "l", "IDLE", "r", oa=8, ob=8, label="опкод выдан", lx=550, ly=86)
    f.edge("IP_OP", "r", "IP_WAIT", "l", label="ip_ready", lx=550, ly=203)
    f.edge("IP_WAIT", "t", "FETCH", "b", label="чтение", lx=708, ly=172, anchor="start")

    # промотка
    f.edge("FETCH", "r", "SCAN", "l", cls="wacc", label="scanning_q", lx=830, ly=52,
           lcls="tacc")
    f.edge("SCAN", "b", "LOOP_OP", "t", oa=20, ob=20, cls="wacc", label="скобка", lx=988,
           ly=150, anchor="start", lcls="tacc")
    f.edge("SCAN", "b", "IP_OP", "t", oa=-30, ob=30, cls="wacc", via=[(930, 140), (430, 140)],
           label="не скобка", lx=600, ly=156, lcls="tacc")
    f.edge("LOOP_OP", "b", "LOOP_WAIT", "t", cls="wacc", label="loop_ready", lx=968, ly=290,
           anchor="start", lcls="tacc")
    f.edge("LOOP_WAIT", "l", "IP_OP", "b", cls="wacc",
           via=[(840, 360), (840, 330), (400, 330)], label="пара не найдена: дальше",
           lx=620, ly=324, lcls="tacc")
    f.edge("LOOP_WAIT", "r", "IDLE", "t", via=[(1070, 360), (1070, 20), (400, 20)],
           label="пара найдена или переполнение 99→0", lx=735, ly=14)

    # загрузка программы
    f.edge("IP_WAIT", "b", "INSN_IN", "b", oa=-20, ob=25, via=[(680, 265), (135, 265)],
           label="загрузка", lx=290, ly=259)
    f.edge("IP_WAIT", "b", "HALT", "l", oa=20, via=[(720, 300), (40, 300), (40, 60)],
           label="halt_pending: останов отработан", lx=420, ly=294)
    f.edge("INSN_IN", "r", "IP_OP", "l", oa=10, ob=10, label="ручной ±IP", lx=230, ly=236)
    f.edge("INSN_IN", "b", "WRITE", "t", oa=-20, ob=-20, label="опкод принят", lx=98, ly=330,
           anchor="end")
    f.wire([(158, 360), (196, 360)], label="→ S_IDLE: записан", lx=202, ly=364)
    f.text(16, 414, "S_INSN_IN → S_IDLE: конец передачи (EOT) или загрузка снята", "tl")

    # сброс счётчиков по команде
    f.box(470, 372, 340, 52, None, [], cls="blk-opt")
    f.text(484, 393, "CLRI, CLRL: IDLE → S_CLR_OP → S_CLR_WAIT → IDLE", "tm")
    f.text(484, 409, "сброс IP или счётчика вложенности", "tl")
    f.text(16, 432, "soft_rst | hard_rst → S_IDLE из любого состояния", "tl")
    return f.render()
