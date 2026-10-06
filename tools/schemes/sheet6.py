"""Лист 6. Управление машиной MachineCtrl."""
from lib import Fig


def fig_mctrl():
    f = Fig("mc", 1200, 520,
            "Управление машиной: автомат исполнения принимает команды пульта и терминала, "
            "дешифрует инструкцию по паре режим-опкод и раздаёт операции линии выборки, "
            "линии данных и реле времени сброса.")
    # пульт
    f.text(12, 30, "ПУЛЬТ", "tf")
    for y, n in ((62, "halt_key"), (84, "step_key"), (106, "run_key"),
                 (128, "key_insn_loading_*")):
        f.pin_in(12, y, 200, n)
    f.text(12, 166, "ТУМБЛЕРЫ", "tf")
    for y, n in ((196, "echo_mode, run_on_*_rst"), (218, "soft_rst_on_eot, bell_on_*")):
        f.pin_in(12, y, 200, n)
    f.text(12, 256, "ТЕРМИНАЛ", "tf")
    f.pin_in(12, 286, 200, "rx_vld, tx_rdy")
    f.wire([(200, 312), (16, 312)], label="tx_vld", lx=20, ly=305, lcls="tp")
    f.text(12, 350, "ИНДИКАЦИЯ", "tf")
    for y, n in ((380, "bell"), (402, "is_halted, insn_mode"), (424, "state[3:0]"),
                 (446, "iret — эмулятор")):
        f.wire([(200, y), (16, y)], label=n, lx=20, ly=y - 7, lcls="tp")

    f.box(200, 40, 260, 440, "Автомат исполнения",
          ["one_step — шаговый режим", "insn_mode — 0 Debug, 1 BF",
           "rst_type — HARD / SOFT", "", "echo_pending — эхо после CIN",
           "bell_pending, error_flag", "",
           "loop_overflow → S_HALT", "soft_rst | hard_rst →", "S_RST_WAIT из любого"],
          align="start", top=24)

    # линия выборки
    f.box(860, 40, 320, 130, "IpLine", ["линия выборки инструкций"], cls="blk-opt")
    f.wire([(460, 60), (860, 60)], label="ip_valid · ip_op[1:0] · insn_loading", lx=470, ly=53)
    f.wire([(860, 86), (460, 86)], label="ip_ready · loop_overflow", lx=470, ly=79)
    f.wire([(860, 112), (640, 112), (640, 290)], label="insn · insn_valid", lx=650, ly=105)

    # признак нуля для скобок
    f.box(690, 130, 110, 50, "MUX", ["insn_mode ? d : a"], top=20, bcls="tpi")
    f.wire([(460, 155), (690, 155)], label="insn_mode", lx=470, ly=148)
    f.wire([(800, 155), (860, 155)], "wacc")
    f.text(868, 159, "← loop_val_zero", "tacc")

    # линия данных
    f.box(860, 200, 320, 130, "ApLine", ["линия данных"], cls="blk-opt")
    f.wire([(460, 220), (860, 220)], label="ap_valid · ap_op[3:0] · ap_dec", lx=470, ly=213)
    f.wire([(860, 246), (460, 246)], label="ap_ready · data_zero_valid", lx=470, ly=239)
    f.wire([(860, 272), (745, 272), (745, 180)], "wacc",
           label="data_zero · ap_zero", lx=852, ly=266, anchor="end", lcls="tacc")

    # дешифратор
    f.box(520, 290, 260, 136, "Дешифратор",
          ["{insn_mode, insn}: 5 бит", "x0 NOP · x1 HALT · xE/xF ISA",
           "x6/x7 скобки; BF и нет", "data_zero_valid → AP_TEST",
           "02…0D: BELL SOT CLR* RST", "12…1D: + − > < . , [-] …"], top=22, bcls="tm")
    f.wire([(520, 380), (460, 380)], label="команда", lx=466, ly=373)

    # реле времени сброса
    f.box(860, 380, 320, 110, "RstTimeRelay", ["держит линию сброса", "заданное время"],
          cls="blk-opt")
    f.wire([(460, 450), (860, 450)], label="soft_rst_req · hard_rst_req", lx=470, ly=443)
    f.wire([(860, 474), (460, 474)], label="rst_busy · soft_rst · hard_rst", lx=470, ly=467)
    return f.render()


def fig_mctrl_fsm():
    f = Fig("mcfsm", 1100, 480,
            "Автомат MachineCtrl: выборка, дешифрация и одна операция над линией выборки, "
            "линией данных, терминалом или реле сброса; после каждой инструкции — в IDLE или, "
            "в шаговом режиме и по кнопке останова, в HALT.")
    f.state("HALT", 380, 60, "S_HALT", cls="st-acc")
    f.state("IDLE", 640, 60, "S_IDLE")
    f.state("FETCH", 900, 60, "S_FETCH")
    f.state("RST_REQ", 120, 180, "S_RST_REQ")
    f.state("CIN_WAIT", 380, 180, "S_CIN_WAIT")
    f.state("DECODE", 640, 180, "S_DECODE")
    f.state("FETCH_W", 900, 180, "S_FETCH_W")
    f.state("RST_WAIT", 120, 300, "S_RST_WAIT")
    f.state("AP_OP", 380, 300, "S_AP_OP")
    f.state("COUT", 640, 300, "S_COUT")
    f.state("IP_OP", 900, 300, "S_IP_OP")
    f.state("AP_OP_W", 380, 420, "S_AP_OP_W")
    f.state("ECHO", 640, 420, "S_ECHO")
    f.state("IP_OP_W", 900, 420, "S_IP_OP_W")

    f.edge("HALT", "r", "IDLE", "l", oa=-8, ob=-8, label="step · run · run_on_rst · загрузка",
           lx=510, ly=45)
    f.edge("IDLE", "l", "HALT", "r", oa=8, ob=8, label="halt_key", lx=510, ly=86)
    f.edge("IDLE", "r", "FETCH", "l", label="IP_NEXT", lx=770, ly=53)
    f.edge("FETCH", "b", "FETCH_W", "t", label="ip_ready", lx=908, ly=124, anchor="start")
    f.edge("FETCH_W", "l", "DECODE", "r", label="insn_valid", lx=770, ly=173)
    f.edge("FETCH_W", "r", "HALT", "t", via=[(1040, 180), (1040, 18), (380, 18)],
           label="загрузка прервана кнопкой или остановом", lx=710, ly=12)
    f.edge("DECODE", "t", "IDLE", "b", oa=30, ob=30,
           label="NOP · ISA · BELL · SOT · скобка", lx=678, ly=124, anchor="start")
    f.edge("DECODE", "t", "HALT", "b", oa=-30, ob=20, via=[(610, 120), (400, 120)],
           label="HALT", lx=505, ly=114)
    f.edge("DECODE", "t", "RST_REQ", "t", oa=-45, via=[(595, 140), (120, 140)],
           label="HRST · SRST", lx=240, ly=134)
    f.edge("DECODE", "l", "CIN_WAIT", "r", label="CIN", lx=510, ly=173)
    f.edge("CIN_WAIT", "t", "HALT", "b", oa=-20, ob=-20, label="halt_key", lx=352, ly=124,
           anchor="end")
    f.edge("CIN_WAIT", "b", "AP_OP", "t", label="rx_vld: AP_CIN", lx=372, ly=262,
           anchor="end")
    f.edge("DECODE", "b", "AP_OP", "t", oa=-30, ob=30, via=[(610, 236), (410, 236)],
           label="операции ApLine, AP_TEST", lx=505, ly=230)
    f.edge("DECODE", "b", "COUT", "t", cls="wwarn", label="COUT: сразу tx_vld", lx=632,
           ly=258, anchor="end", lcls="twarn")
    f.edge("DECODE", "b", "IP_OP", "t", oa=30, ob=-20, via=[(670, 236), (880, 236)],
           label="CLRL · CLRI", lx=775, ly=230)
    f.edge("RST_REQ", "b", "RST_WAIT", "t", label="rst_busy", lx=128, ly=244, anchor="start")
    f.edge("RST_WAIT", "l", "HALT", "l", via=[(40, 300), (40, 60)],
           label="реле отпущено: ISA по типу сброса", lx=180, ly=54)
    f.wire([(16, 372), (120, 372), (120, 317)], "wd")
    f.text(16, 390, "soft_rst | hard_rst из любого состояния", "tl")

    f.edge("AP_OP", "b", "AP_OP_W", "t", label="ap_ready", lx=388, ly=364, anchor="start")
    f.edge("AP_OP_W", "r", "ECHO", "l", oa=8, ob=8, label="echo_pending", lx=545, ly=446)
    f.edge("IP_OP", "b", "IP_OP_W", "t", label="ip_ready", lx=908, ly=364, anchor="start")
    for key, side in (("COUT", "r"), ("ECHO", "r"), ("IP_OP_W", "r")):
        x, y = f.sp(key, side)
        f.wire([(x, y), (x + 30, y)], label="IDLE / HALT", lx=x + 36, ly=y + 4)
    x, y = f.sp("AP_OP_W", "l")
    f.wire([(x, y), (x - 30, y)], label="IDLE / HALT", lx=x - 36, ly=y + 4, anchor="end")
    f.text(16, 456, "IDLE / HALT = (halt_key | one_step) ? S_HALT : S_IDLE", "tl")
    f.text(16, 474, "loop_overflow → S_HALT из любого состояния", "tl")
    return f.render()
