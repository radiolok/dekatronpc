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
    for y, n in ((196, "echo_mode, soft_rst_on_eot"), (218, "run_on_*_rst, bell_on_* → реле")):
        f.pin_in(12, y, 200, n)
    f.text(16, 240, "реле 2CO ×5, 0 ламп", "tl")
    f.text(12, 256, "ТЕРМИНАЛ", "tf")
    f.pin_in(12, 286, 200, "rx_vld, tx_rdy")
    f.wire([(200, 312), (16, 312)], label="tx_vld, rx_rdy (конец CIN)", lx=20, ly=305, lcls="tp")
    f.text(12, 350, "ИНДИКАЦИЯ", "tf")
    for y, n in ((380, "bell"), (402, "is_halted, insn_mode"), (424, "state[3:0]"),
                 (446, "iret — эмулятор")):
        f.wire([(200, y), (16, y)], label=n, lx=20, ly=y - 7, lcls="tp")

    f.box(200, 40, 260, 440, "Автомат исполнения",
          ["state[3:0] — 10 состояний", "one_step — шаговый режим",
           "insn_mode — 0 Debug, 1 BF", "insn_loading", "rst_soft — тип сброса",
           "overflow_q — фронт переполнения",
           "op_q — код инструкции (P3)", "pf_q — следующая уже выбрана",
           "стробы — дешифрация state,", "valid только при go:",
           "go = ip_ready · ap_ready", "      · ~(soft_rst | hard_rst)", "",
           "loop_overflow↑ → S_HALT", "soft_rst | hard_rst →", "S_RST_WAIT из любого"],
          align="start", top=24)

    # линия выборки
    f.box(860, 40, 320, 130, "IpLine", ["линия выборки инструкций"], cls="blk-opt")
    f.wire([(460, 60), (860, 60)], label="ip_valid · ip_clr · ip_ahead · insn_loading", lx=470, ly=53)
    f.wire([(860, 86), (460, 86)], label="ip_ready · loop_overflow", lx=470, ly=79)
    f.wire([(860, 112), (640, 112), (640, 290)], label="insn · insn_valid · insn_eot", lx=650, ly=105)

    # признак нуля для скобок
    f.box(690, 130, 110, 50, "MUX", ["insn_mode ? d : a"], top=20, bcls="tpi")
    f.wire([(460, 155), (690, 155)], label="insn_mode", lx=470, ly=148)
    f.wire([(800, 155), (860, 155)], "wacc")
    f.text(868, 159, "← loop_val_zero", "tacc")

    # линия данных
    f.box(860, 200, 320, 130, "ApLine", ["линия данных"], cls="blk-opt")
    f.wire([(460, 220), (860, 220)], label="ap_valid; ap_op = {insn_mode, op_q}", lx=470, ly=213)
    f.wire([(860, 246), (460, 246)], label="ap_ready · data_zero_valid", lx=470, ly=239)
    f.wire([(860, 272), (745, 272), (745, 180)], "wacc",
           label="data_zero · ap_zero", lx=852, ly=266, anchor="end", lcls="tacc")

    # дешифратор
    f.box(520, 290, 260, 136, "Дешифратор",
          ["{insn_mode, op_q}: 5 бит", "ip_clr = S_EXEC · CLRL/CLRI",
           "op_q ← insn в FETCH_W и в конце", "x6/x7 скобки; BF и нет",
           "data_zero_valid → скобка в ApLine", "12…1D: + − > < . , [-] …"], top=22, bcls="tm")
    f.wire([(520, 380), (460, 380)], label="команда", lx=466, ly=373)

    # реле времени сброса
    f.box(860, 380, 320, 110, "RstTimeRelay", ["держит линию сброса", "заданное время"],
          cls="blk-opt")
    f.wire([(460, 450), (860, 450)], label="soft_rst_req · hard_rst_req", lx=470, ly=443)
    f.wire([(860, 474), (460, 474)], label="rst_busy · soft_rst · hard_rst", lx=470, ly=467)
    return f.render()


def fig_mctrl_fsm():
    f = Fig("mcfsm", 1100, 480,
            "Автомат MachineCtrl: S_IDLE выдаёт выборку, S_DECODE дешифрует, S_EXEC выдаёт одну "
            "операцию линии выборки или линии данных (операции ApLine, кроме TEST, — вместе с "
            "выборкой следующей), S_WAIT ждёт её окончания; после каждой инструкции — в IDLE, "
            "сразу в DECODE, если следующая уже выбрана, или в HALT.")
    f.state("HALT", 380, 60, "S_HALT", cls="st-acc")
    f.state("IDLE", 640, 60, "S_IDLE")
    f.state("RST_REQ", 120, 180, "S_RST_REQ")
    f.state("CIN_WAIT", 380, 180, "S_CIN_WAIT")
    f.state("DECODE", 640, 180, "S_DECODE")
    f.state("FETCH_W", 900, 180, "S_FETCH_W")
    f.state("RST_WAIT", 120, 300, "S_RST_WAIT")
    f.state("WAIT", 380, 300, "S_WAIT")
    f.state("EXEC", 640, 300, "S_EXEC")
    f.state("COUT", 900, 300, "S_COUT")

    f.edge("HALT", "r", "IDLE", "l", oa=-8, ob=-8, label="step · run · загрузка",
           lx=510, ly=45)
    f.edge("IDLE", "l", "HALT", "r", oa=8, ob=8, label="halt_key", lx=510, ly=86)
    f.edge("IDLE", "r", "FETCH_W", "t", via=[(900, 60)], label="go: ip_valid, выборка",
           lx=770, ly=53)
    f.edge("FETCH_W", "l", "DECODE", "r", label="go · insn_valid", lx=770, ly=173)
    f.edge("FETCH_W", "r", "HALT", "t", via=[(1040, 180), (1040, 18), (380, 18)],
           label="загрузка прервана кнопкой или остановом", lx=710, ly=12)
    f.edge("DECODE", "t", "IDLE", "b", oa=30, ob=30,
           label="NOP · ISA · BELL · SOT · скобка", lx=678, ly=124, anchor="start")
    f.edge("DECODE", "t", "HALT", "b", oa=-30, ob=20, via=[(610, 120), (400, 120)],
           label="HALT", lx=505, ly=114)
    f.edge("DECODE", "t", "RST_REQ", "t", oa=-45, via=[(595, 140), (120, 140)],
           label="HRST · SRST · insn_eot", lx=240, ly=134)
    f.edge("DECODE", "l", "CIN_WAIT", "r", label="CIN", lx=510, ly=173)
    f.edge("CIN_WAIT", "t", "HALT", "b", oa=-20, ob=-20, label="halt_key", lx=352, ly=124,
           anchor="end")
    f.edge("CIN_WAIT", "b", "WAIT", "t", label="rx_vld · go: CIN", lx=372, ly=244,
           anchor="end")
    f.edge("DECODE", "b", "EXEC", "t", label="CLR* · операции ApLine · TEST · COUT", lx=648,
           ly=244, anchor="start")
    f.edge("EXEC", "l", "WAIT", "r", label="go: ip_valid | ap_valid", lx=510, ly=293)
    f.text(510, 336, "ApLine, кроме TEST: с выборкой", "tl", anchor="middle")
    f.edge("WAIT", "b", "COUT", "b", via=[(380, 370), (900, 370)],
           label="go · COUT | CIN · echo_mode", lx=640, ly=364)
    f.edge("RST_REQ", "b", "RST_WAIT", "t", label="rst_busy", lx=128, ly=244, anchor="start")
    f.edge("RST_WAIT", "l", "HALT", "l", via=[(40, 300), (40, 60)],
           label="~rst_busy: ISA по типу сброса", lx=180, ly=54)
    f.text(16, 340, "при run_on_*_rst — в S_IDLE", "tl")
    f.text(16, 400, "soft_rst | hard_rst → S_RST_WAIT из любого состояния", "tl")

    x, y = f.sp("WAIT", "l")
    f.wire([(x, y), (x - 30, y)], label="go: s_next", lx=x - 36, ly=y + 4, anchor="end")
    x, y = f.sp("COUT", "r")
    f.wire([(x, y), (x + 30, y)], label="tx_rdy:", lx=x + 36, ly=y - 4)
    f.text(x + 36, y + 12, "s_next", "tl")
    f.text(16, 438, "s_next = (halt_key | one_step) ? S_HALT : pf_q ? S_DECODE : S_IDLE   (pf_q — следующая уже выбрана)", "tl")
    f.text(16, 456, "фронт loop_overflow → S_HALT из любого состояния (REQ-CTLV2-005)", "tl")
    f.text(16, 474, "стробы: ip_valid, ap_valid, tx_vld = S_COUT, rx_rdy = S_WAIT · CIN · go, *_rst_req = S_RST_REQ", "tl")
    return f.render()
