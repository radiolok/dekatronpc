"""Модель выборки инструкций IpLine.

Работает ИСКЛЮЧИТЕЛЬНО с опкодами, как RTL: память программ хранит
четырёхбитовые значения, распознавание скобок идёт по опкоду через
InsnLoopDetector. Символов на этом уровне нет и быть не может —
преобразование символ/опкод выполняется в загрузчике программ.
"""

# Опкоды скобок одинаковы в обоих наборах команд:
#   Debug ISA: 0x6 = LABEG '{', 0x7 = LAEND '}'
#   BF ISA:    0x6 = LBEG  '[', 0x7 = LEND  ']'
# Поэтому детектор скобок не зависит от режима — как в RTL.
OP_LOOP_OPEN  = 0x6
OP_LOOP_CLOSE = 0x7
OP_NOP        = 0x0


def insn_loop_detector(opcode):
    """Копия модуля InsnLoopDetector: (LoopOpen, LoopClose)."""
    return (opcode == OP_LOOP_OPEN, opcode == OP_LOOP_CLOSE)


class IpLine:
    def __init__(s, program_opcodes, ip=0):
        assert all(isinstance(o, int) and 0 <= o <= 0xF for o in program_opcodes), \
            "память программ хранит только 4-битные опкоды"
        s.mem = list(program_opcodes)
        s.ip = ip
        s.loop = 0
        s.insn = OP_NOP
        s.insn_valid = False
        s.ip_counted = False          # IP уже сдвинут под текущую инструкцию
        s.overflow = False
        s.reads = 0
        s.ip_steps = 0
        s.loop_steps = 0

    # ---- обращения к памяти программ -------------------------------
    def _read(s):
        s.reads += 1
        return s.mem[s.ip] if 0 <= s.ip < len(s.mem) else OP_NOP

    def _step_ip(s, dec):
        s.ip_steps += 1
        s.ip = s.ip - 1 if dec else s.ip + 1

    def _step_loop(s, dec):
        s.loop_steps += 1
        if dec:
            s.loop -= 1
        else:
            s.loop += 1
            if s.loop > 999:          # перевал через 999 при инкременте
                s.overflow = True
                s.loop = 0

    # ---- операции командного интерфейса ----------------------------
    def op_clr_ip(s):
        s.ip = 0
        s.ip_counted = False
        s.insn_valid = False

    def op_clr_loop(s):
        s.loop = 0
        s.overflow = False

    def op_next(s, loop_val_zero):
        """Выдать следующую инструкцию (опкод)."""
        if not s.ip_counted:
            # Первая выборка после сброса: читаем по текущему адресу
            s.ip_counted = True
            s.insn = s._read()
            s.insn_valid = True
            return s.insn

        cur_open, cur_close = insn_loop_detector(s.insn)
        scan_fwd  = cur_open  and loop_val_zero
        scan_back = cur_close and not loop_val_zero

        if not (scan_fwd or scan_back):
            s._step_ip(dec=False)
            s.insn = s._read()
            return s.insn

        # ---- промотка тела цикла ----------------------------------
        dec = scan_back
        s._step_loop(dec=False)        # своя скобка углубляет вложенность
        while True:
            s._step_ip(dec=dec)
            opcode = s._read()
            is_open, is_close = insn_loop_detector(opcode)
            if is_open or is_close:
                # своя скобка углубляет, ответная поднимает
                loop_dec = is_open if scan_back else is_close
                s._step_loop(dec=loop_dec)
                if s.overflow:
                    # Глубина вложенности превысила возможности машины.
                    # Промотку надо прервать, иначе парная скобка не
                    # найдётся никогда и машина зависнет.
                    s.insn = opcode
                    return s.insn
                if loop_dec and s.loop == 0:
                    s.insn = opcode
                    return s.insn
            # Выход за пределы памяти программ также прерывает промотку
            if not (0 <= s.ip < len(s.mem)):
                s.overflow = True
                s.insn = OP_NOP
                return s.insn
