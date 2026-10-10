"""Лист 5. Линия данных ApLine с ленивым чтением."""
from lib import Fig


def fig_apline():
    f = Fig("apl", 1160, 500,
            "Линия данных: счётчик адреса и счётчик данных на декатронах, порт памяти "
            "данных с выходным регистром. Значение ячейки берётся из счётчика, если он "
            "захвачен, иначе прямо из выходного регистра памяти.")
    for y, n in ((62, "valid"), (84, "op = {mode, insn}")):
        f.pin_in(12, y, 170, n)
    f.wire([(170, 132), (16, 132)], label="ready", lx=20, ly=125, lcls="tp")
    f.wire([(170, 160), (16, 160)], label="mem_lock", lx=20, ly=153, lcls="tp")
    f.box(170, 40, 230, 210, "Автомат и флаги",
          ["lock_q — MemLock: счётчик", "владеет ячейкой", "",
           "mem_here_q — регистр памяти", "относится к текущему AP", "",
           "op держит память программ", "dec = op[0]"], align="start", top=22)

    # счётчик адреса
    f.wire([(400, 70), (500, 70)], label="valid · set_zero", lx=406, ly=63)
    f.wire([(500, 108), (400, 108)], label="ready", lx=406, ly=101)
    f.box(500, 40, 220, 100, "DekatronCounter · AP",
          ["5 декад, 0…29999", "TOP_LIMIT_MODE", "29999+1 → 0, 0−1 → 29999"])
    f.wire([(610, 140), (610, 166)])
    f.text(610, 180, "ap_zero → MachineCtrl", "tp", "middle")

    # счётчик данных
    f.wire([(400, 220), (500, 220)], label="valid · set(_zero)", lx=406, ly=213)
    f.wire([(500, 258), (400, 258)], label="ready · zero", lx=406, ly=251)
    f.box(500, 200, 220, 100, "DekatronCounter · Data",
          ["3 декады, 0…255", "READ + WRITE", "255+1 → 0, 0−1 → 255"])

    # память данных (снаружи)
    f.wire([(720, 90), (1000, 90), (1000, 150)], label="mem_addr = AP", lx=740, ly=83)
    f.wire([(285, 40), (285, 20), (1060, 20), (1060, 150)],
           label="mem_valid · mem_wr", lx=670, ly=14, anchor="middle")
    f.wire([(1080, 150), (1080, 34), (1110, 34)], start_arrow=True, arrow=False)
    f.text(1114, 38, "ready", "tpi")
    f.wire([(720, 230), (900, 230)], label="mem_wr_data = out", lx=730, ly=223)
    f.box(900, 150, 200, 150, "Ram · данные", ["вне ApLine", "100 000 × 10 бит", "",
                                                "rd_data — выходной", "регистр, держит", "последнюю ячейку"],
          cls="blk-opt")

    # путь значения ячейки из памяти
    f.wire([(1000, 300), (1000, 330), (460, 330), (460, 360)], "wacc",
           label="mem_rd_data", lx=1006, ly=318, lcls="tacc")
    f.dot(940, 330, "dot-acc")
    f.wire([(940, 330), (940, 370)], "wacc")

    # вход счётчика данных
    # rx_data_bcd держит терминал до rx_vld & rx_rdy: входного регистра нет
    f.pin_in(12, 385, 420, "rx_data_bcd (держит терминал)")
    f.box(420, 360, 80, 50, "MUX", ["CIN ? rx"], top=20, bcls="tpi")
    f.wire([(500, 385), (610, 385), (610, 300)], label="data_in", lx=520, ly=378)

    # выходы
    f.wire([(720, 270), (790, 270), (790, 370)], label="data_out · zero", lx=730, ly=263)
    f.box(740, 370, 240, 92, None, [], cls="blk")
    f.lines(752, 390, ["tx  = data_out (всегда)", "zero = lock ? zero : rd_data = 0",
                       "zero_valid = lock | mem_here"], "tm", lh=20)
    f.wire([(390, 250), (390, 484), (860, 484), (860, 462)], "wd",
           label="lock_q · mem_here_q", lx=520, ly=478)
    f.pin_out(980, 390, 1010, "tx_data_bcd")
    f.pin_out(980, 412, 1010, "data_zero")
    f.pin_out(980, 434, 1010, "data_zero_valid")
    return f.render()


def fig_apline_fsm():
    f = Fig("aplfsm", 1000, 270,
            "Автомат ApLine: память читается только тогда, когда значение ячейки нужно и его "
            "нет ни в счётчике, ни в выходном регистре памяти; выгрузка — перед сменой "
            "адреса, если счётчик владеет ячейкой (MemLock). Каждое состояние, кроме S_IDLE, выдаёт одну "
            "операцию, когда готовы все исполнители (go), и уходит в такте её приёма.")
    f.dy = 20
    f.state("READ", 150, 60, "S_READ", cls="st-acc")
    f.state("IDLE", 470, 60, "S_IDLE", cls="st-acc")
    f.state("FLUSH", 790, 60, "S_FLUSH")
    f.state("DSET", 150, 200, "S_DSET")
    f.state("DOP", 470, 200, "S_DOP")
    f.state("AP", 790, 200, "S_AP")

    f.selfloop("IDLE", "t", label="COUT: lock · TEST: ячейка рядом · CLRML: нет lock", lx=448, ly=14, anchor="end")
    f.edge("IDLE", "l", "READ", "r", oa=-8, ob=-8, cls="wacc", label="ячейка нужна и её нет",
           lx=310, ly=45, lcls="tacc")
    f.edge("READ", "r", "IDLE", "l", oa=8, ob=8, label="TEST", lx=310, ly=86)
    f.edge("READ", "b", "DSET", "t", oa=-20, ob=-20, cls="wacc", label="STEP, LOAD, COUT",
           lx=122, ly=135, anchor="end", lcls="tacc")
    f.edge("IDLE", "b", "DSET", "t", oa=-30, ob=20, via=[(440, 130), (170, 130)],
           label="mem_here: STEP, LOAD, COUT · CIN", lx=305, ly=124)
    f.edge("IDLE", "b", "DOP", "t", label="lock: STEP · DATA_ZERO", lx=478, ly=160,
           anchor="start")
    f.edge("IDLE", "r", "FLUSH", "l", oa=-8, ob=-8, label="lock: шаг AP, CLRML · STORE",
           lx=630, ly=45)
    f.edge("FLUSH", "l", "IDLE", "r", oa=8, ob=8, label="STORE · CLRML: lock ← 0", lx=630, ly=86)
    f.edge("IDLE", "b", "AP", "t", oa=30, ob=-20, via=[(500, 130), (770, 130)],
           label="нет lock: шаг AP", lx=640, ly=124)
    f.edge("FLUSH", "b", "AP", "t", oa=20, ob=20, label="шаг AP: lock ← 0", lx=818, ly=135,
           anchor="start")
    f.edge("AP", "r", "IDLE", "t", ob=35, via=[(920, 200), (920, 12), (505, 12)],
           label="mem_here ← 0", lx=710, ly=6)
    f.edge("DSET", "r", "DOP", "l", label="STEP", lx=310, ly=194)
    f.wire([(150, 217), (150, 240), (190, 240)], label="→ S_IDLE: LOAD, CIN", lx=196, ly=244)
    f.wire([(470, 217), (470, 240), (510, 240)], label="→ S_IDLE: lock ← 1",
           lx=516, ly=244)
    return f.render()
