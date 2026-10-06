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
           "scanning_q — идёт промотка", "",
           "dir_q — шаг IP назад", "(промотка, кнопка −IP)", "",
           "overflow_q — глубина > 99", "",
           "стробы — из state (Мур)"], align="start", top=22)

    # счётчик инструкций
    f.wire([(420, 70), (560, 70)], label="valid · dec", lx=428, ly=63)
    f.wire([(560, 108), (420, 108)], label="ready", lx=428, ly=101)
    f.box(560, 40, 210, 100, "DekatronCounter · IP",
          ["5 декад, 0…99999", "HARD_RST_D_CNT = 3", "hard_rst → 99900", "soft_rst → 00000"])

    # счётчик циклов
    f.wire([(420, 186), (560, 186)], label="valid · dec · set_zero", lx=428, ly=179)
    f.wire([(560, 224), (420, 224)], label="zero", lx=428, ly=217)
    f.box(560, 168, 210, 80, "DekatronCounter · Loop",
          ["2 декады, 0…99", "LOOP_DEKATRON_NUM = 2", "переход через 0 = переполнение"])

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
           label="rd_data", lx=1012, ly=300, lcls="tacc")
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
            "Автомат IpLine. Основной цикл: шаг IP, запрос чтения, приём опкода. Ветвь "
            "промотки: разбор скобки, шаг счётчика вложенности, снова шаг IP до парной "
            "скобки. Каждое состояние, выдающее операцию, ждёт go — готовности обоих "
            "счётчиков и памяти — и уходит в такте её приёма.")
    f.state("HALT", 110, 60, "S_HALT")
    f.state("IDLE", 400, 60, "S_IDLE", cls="st-acc")
    f.state("FETCH", 700, 60, "S_FETCH")
    f.state("FETCH_W", 960, 60, "S_FETCH_W")
    f.state("INSN_IN", 110, 210, "S_INSN_IN")
    f.state("IP", 400, 210, "S_IP")
    f.state("LOOP", 700, 210, "S_LOOP")
    f.state("SCAN", 960, 210, "S_SCAN_EVAL")
    f.state("WRITE", 110, 360, "S_WRITE")

    # останов
    f.edge("HALT", "r", "IDLE", "l", oa=-8, ob=-8, label="halt_rq снят", lx=255, ly=45)
    f.edge("IDLE", "l", "HALT", "r", oa=8, ob=8, label="halt_rq, IP не сдвинут", lx=255, ly=86)
    f.edge("HALT", "b", "IP", "l", oa=20, ob=-12, via=[(130, 160), (280, 160), (280, 198)],
           label="кнопка ±IP", lx=205, ly=176)

    # из IDLE вниз
    f.edge("IDLE", "b", "INSN_IN", "t", oa=-35, ob=-30, via=[(365, 120), (80, 120)],
           label="загрузка с текущего адреса", lx=220, ly=114)
    f.edge("IDLE", "b", "IP", "t", oa=-15, ob=-15, cls="wwarn", label="останов: IP+1",
           lx=378, ly=178, anchor="end", lcls="twarn")
    f.edge("IDLE", "b", "IP", "t", oa=10, ob=10, label="шаг IP", lx=418, ly=170,
           anchor="start")
    f.edge("IDLE", "b", "LOOP", "t", oa=35, via=[(435, 120), (700, 120)],
           cls="wacc", label="скобка: промотка", lx=455, ly=114, anchor="start", lcls="tacc")

    # основной цикл
    f.edge("IDLE", "r", "FETCH", "l", oa=-8, ob=-8, label="IP не сдвинут: чтение на месте",
           lx=550, ly=45)
    f.edge("IP", "r", "FETCH", "l", oa=-10, ob=8, via=[(600, 200), (600, 68)],
           label="go: шаг выдан", lx=606, ly=170, anchor="start")
    f.edge("FETCH", "r", "FETCH_W", "l", label="go: чтение выдано", lx=830, ly=52)
    f.edge("FETCH_W", "t", "IDLE", "t", oa=-20, ob=20, via=[(940, 20), (420, 20)],
           label="go: insn_q ← rd_data", lx=680, ly=14)

    # промотка
    f.edge("FETCH_W", "b", "SCAN", "t", cls="wacc", label="scanning_q", lx=968, ly=140,
           anchor="start", lcls="tacc")
    f.edge("SCAN", "l", "LOOP", "r", cls="wacc", label="скобка", lx=830, ly=203,
           lcls="tacc")
    f.edge("SCAN", "b", "IP", "b", oa=-20, ob=-10, cls="wacc", via=[(940, 290), (390, 290)],
           label="не скобка", lx=680, ly=284, lcls="tacc")
    f.edge("LOOP", "b", "IP", "b", ob=20, cls="wacc", via=[(700, 260), (420, 260)],
           label="go: шаг выдан", lx=545, ly=254, lcls="tacc")
    f.text(430, 318, "→ S_IDLE из S_IP: scanning_q и нуль счётчика вложенности — пара найдена",
           "tl")
    f.text(430, 334, "→ S_IDLE из S_SCAN_EVAL: своя скобка при 99 — переполнение, промотка прервана",
           "tl")

    # загрузка программы
    f.edge("IP", "l", "INSN_IN", "r", label="загрузка", lx=200, ly=205)
    f.edge("INSN_IN", "r", "IP", "l", oa=12, ob=12, label="ручной ±IP", lx=255, ly=238)
    f.edge("IP", "b", "HALT", "l", oa=-30, via=[(370, 340), (40, 340), (40, 60)],
           cls="wwarn", label="halt_pending", lx=210, ly=334, lcls="twarn")
    f.edge("INSN_IN", "b", "WRITE", "t", oa=-20, ob=-20, label="опкод принят", lx=98, ly=300,
           anchor="end")
    f.wire([(158, 360), (196, 360)], label="→ S_IDLE: go, запись insn_q выдана", lx=202, ly=364)
    f.text(16, 400, "S_INSN_IN → S_IDLE: конец передачи (EOT) или загрузка снята", "tl")

    # сброс счётчиков по команде
    f.box(560, 372, 420, 52, None, [], cls="blk-opt")
    f.text(574, 393, "CLRI, CLRL: IDLE → S_CLR_IP | S_CLR_LOOP → IDLE", "tm")
    f.text(574, 409, "set_zero выдаётся по go, сброс окончен — ready в S_IDLE", "tl")
    f.text(16, 432, "soft_rst | hard_rst → S_IDLE из любого состояния", "tl")
    return f.render()
