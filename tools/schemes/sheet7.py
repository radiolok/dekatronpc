"""Лист 7. Машина целиком: DekatronPC."""
from lib import Fig


def fig_top():
    f = Fig("top", 1200, 480,
            "Верхний уровень: пульт и терминал, автомат управления, линия выборки со своей "
            "памятью программ, линия данных со своей памятью данных, реле времени, которое "
            "держит физические линии сброса всех счётчиков; второй порт памяти — только для "
            "эмулятора.")
    f.box(20, 40, 180, 160, "Пульт", ["Halt · Step · Run", "InsnLoading Start/Stop",
                                     "SoftRstKey · HardRstKey", "keyNextIp · keyPrevIp",
                                     "тумблеры режимов"], bcls="tl")
    f.box(20, 250, 180, 170, "Терминал", ["tx_data_bcd · tx_vld/rdy", "rx_data_bcd · rx_vld/rdy",
                                         "InsnIn · Valid/Ready", "", "индикация: IP, AP,",
                                         "Loop, Insn, state"], bcls="tl")

    f.box(260, 40, 190, 270, "MachineCtrl", ["автомат исполнения", "дешифратор", "{insn_mode, insn}"])
    f.box(260, 340, 190, 80, "RstTimeRelay", ["выдержка импульса", "сброса"])

    f.box(540, 40, 200, 150, "IpLine", ["IP: 5 декад", "Loop: 2 декады", "insn_q, детектор скобок"])
    f.box(820, 40, 200, 150, "IpMemory", ["Ram 100 000 × 4", "ПЗУ загрузчика 999xx"])
    f.box(540, 250, 200, 150, "ApLine", ["AP: 5 декад", "Data: 3 декады", "lock · dirty · mem_here"])
    f.box(820, 250, 200, 150, "Ram", ["100 000 × 10", "выходной регистр"])
    f.box(1070, 40, 110, 360, "Эмулятор", ["2-й порт", "чтения"], cls="blk-opt", top=200)

    # пульт и терминал
    f.wire([(200, 100), (260, 100)], label="кнопки", lx=206, ly=93)
    f.wire([(200, 170), (230, 170), (230, 380), (260, 380)], label="Rst keys", lx=206, ly=163)
    f.wire([(110, 40), (110, 20), (640, 20), (640, 40)], label="keyNextIp · keyPrevIp",
           lx=375, ly=14, anchor="middle")
    f.wire([(200, 280), (260, 280)], start_arrow=True, label="vld/rdy", lx=206, ly=273)
    f.wire([(110, 420), (110, 440), (640, 440), (640, 400)], start_arrow=True,
           label="rx_data_bcd · tx_data_bcd", lx=470, ly=434)
    f.wire([(170, 420), (170, 458), (775, 458), (775, 170), (740, 170)],
           label="InsnIn · Valid/Ready", lx=470, ly=472)

    # управление линиями
    f.wire([(450, 80), (540, 80)], label="ip_op", lx=460, ly=73)
    f.wire([(540, 120), (450, 120)], label="insn", lx=460, ly=113)
    f.wire([(450, 270), (540, 270)], label="ap_op", lx=460, ly=263)
    f.wire([(540, 296), (450, 296)], label="zero", lx=460, ly=289)
    f.wire([(330, 310), (330, 340)])
    f.wire([(380, 340), (380, 310)])
    f.text(338, 330, "req", "tn")
    f.text(388, 330, "busy · rst", "tn")

    # физические линии сброса
    f.wire([(450, 400), (500, 400), (500, 160), (540, 160)], "wacc",
           label="soft_rst · hard_rst", lx=456, ly=414, lcls="tacc")
    f.dot(500, 370, "dot-acc")
    f.wire([(500, 370), (540, 370)], "wacc")

    # память
    f.wire([(740, 90), (820, 90)], label="addr · wr", lx=748, ly=83)
    f.wire([(820, 130), (740, 130)], label="rd_data", lx=748, ly=123)
    f.wire([(740, 300), (820, 300)], label="addr · wr", lx=748, ly=293)
    f.wire([(820, 340), (740, 340)], "wacc", label="rd_data", lx=748, ly=333, lcls="tacc")
    f.wire([(1020, 115), (1070, 115)], "wd", start_arrow=True)
    f.wire([(1020, 325), (1070, 325)], "wd", start_arrow=True)
    return f.render()
