//======================================================================
// MachineCtrl — верхний конечный автомат машины
//----------------------------------------------------------------------
// Объединяет IpLine и ApLine, декодирует инструкции, обслуживает
// терминал, панель управления и сбросы.
//
//----------------------------------------------------------------------
// ЧТО УШЛО ОТНОСИТЕЛЬНО ПРЕЖНЕГО InsnDecoder
//
// 0. Признак нуля ячейки при ленивом чтении не всегда под рукой, поэтому
//    перед скобкой декодер просит ApLine его обеспечить, выдав ему
//    саму скобку как операцию. Это одно обращение к памяти на проверку скобки и только
//    если значение ещё не прочитано. Взамен перемещения указателя не
//    трогают память вовсе: на программе вычисления Pi это даёт на 36%
//    меньше обращений.
//
// 1. Логика циклов. Прежде декодер сам решал по '[' и ']', надо ли
//    перематывать, и повторно поднимал IpRequest:
//        5'h?6: if (LoopValZero) IpRequest <= 1'b1; else state <= EXEC;
//    Теперь промотку целиком выполняет IpLine: он получает признак
//    loop_val_zero и сам решает, куда и насколько мотать. Декодеру
//    остаётся выдать обычный запрос следующей инструкции, а скобки
//    выполняются как пустая операция.
//
// 2. Ветвление IpRequest/ApRequest/DataRequest на отдельные импульсные
//    линии. Заменено на два интерфейса Valid/Ready. Кода операции
//    ApLine не получает отсюда: им служит сама инструкция {insn_mode,
//    insn}, и дешифрирует её ApLine (REQ-APV2-008). IpLine получает
//    один бит clr: следующая инструкция или исполнение CLRL/CLRI.
//
// 3. Асинхронные входы Rst_n/HardRst_n, дёргавшие всю логику из двух
//    always-веток. Сброс декатронных счётчиков — физический импульс по
//    катоду, его длительность держит внешнее реле времени. Поэтому
//    машина выдаёт ЗАПРОС сброса и ждёт снятия признака занятости реле.
//
//    Сброс при этом ОБЩЕМАШИННЫЙ: в исходное состояние приводятся и
//    автомат, и режим набора команд, и обе линии. Программный от
//    аппаратного отличается только тем, какой адрес окажется в счётчике
//    инструкций и какой набор команд включится после снятия.
//    Инициатором может быть как инструкция HRST/SRST, так и кнопка на
//    пульте, поэтому машина следит за самими линиями сброса, а не только
//    за собственным запросом.
//
//    rst_n остаётся сбросом одной лишь логики и разряд не двигает.
//
//----------------------------------------------------------------------
// РЕЖИМЫ НАБОРА КОМАНД
//
// Декодирование ведётся по паре {insn_mode, insn}: опкоды 0xB..0xD в
// двух наборах означают разное (CLRA/HRST/SRST против CLRML/LOAD/STORE).
//
//----------------------------------------------------------------------
// УПРЕЖДАЮЩАЯ ВЫБОРКА (P3, doc/prefetch_p3.md)
//
// Операция над ApLine не трогает ни IP, ни память программ, поэтому
// следующая инструкция выбирается одновременно с её исполнением: в такте
// выдачи ap_valid автомат выдаёт и ip_valid (clr = 0). Исключение —
// скобки: решение о промотке IpLine принимает по самой скобке и
// по признаку нуля, который даёт как раз эта операция TEST. CIN тоже не
// выбирает заранее: он ждёт терминал, выигрыша нет.
//
// Выходной регистр памяти программ при этом сменится раньше, чем
// закончится операция, поэтому код текущей инструкции снова
// защёлкивается: op_q (пишется в S_FETCH_W и в последнем такте
// инструкции) служит операцией ApLine и всей дешифрации. По окончании
// операции автомат идёт прямо в S_DECODE, минуя S_IDLE и S_FETCH_W.
//
// IP при этом стоит на следующей, ещё не исполненной инструкции.
// Если машина останавливается в этот момент, IpLine не делает
// обычного шага при останове (вход ip_ahead), а только снимает
// ip_counted_q: после пуска та же инструкция читается заново.
//======================================================================

`include "../DekatronPC/insnValues.sv"

`default_nettype none

module MachineCtrl #(
    parameter bit          EN_EMULATOR   = 1'b0   // счётчик выполненных инструкций
)(
    input  wire clk,
    input  wire rst_n,        // сброс логики; разряд декатронов не двигает

    //------------------------------------------------------------------
    // Пульт управления
    //------------------------------------------------------------------
    input  wire halt_key,
    input  wire step_key,
    input  wire run_key,
    input  wire key_insn_loading_start,
    input  wire key_insn_loading_stop,

    input  wire echo_mode,        // символ из CIN дублируется в COUT
    input  wire run_on_hard_rst,
    input  wire run_on_soft_rst,
    input  wire soft_rst_on_eot,
    input  wire bell_on_cin,      // звонок при ожидании ввода
    input  wire bell_on_halt,
    input  wire bell_on_error,

    //------------------------------------------------------------------
    // Линия выборки инструкций
    //------------------------------------------------------------------
    output logic                  ip_valid,
    input  wire                   ip_ready,
    output wire                   ip_clr,       // CLRL/CLRI, иначе выборка
    output wire                   ip_ahead,     // IP уже на следующей инструкции
    output wire                   loop_val_zero,
    output logic                  insn_loading,
    input  wire [INSN_WIDTH-1:0]  insn,
    input  wire                   insn_valid,
    input  wire                   insn_eot,     // при загрузке принят EOT
    input  wire                   loop_overflow,

    //------------------------------------------------------------------
    // Линия работы с данными. Операция — {insn_mode, insn}
    //------------------------------------------------------------------
    output logic                  ap_valid,
    input  wire                   ap_ready,
    output wire [4:0]             ap_op,        // {insn_mode, op_q}, держится до ready
    input  wire                   data_zero,
    input  wire                   data_zero_valid,
    input  wire                   ap_zero,
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                   mem_lock,
/* verilator lint_on UNUSEDSIGNAL */

    //------------------------------------------------------------------
    // Терминал
    //------------------------------------------------------------------
    output logic                  tx_vld,
    input  wire                   tx_rdy,
    input  wire                   rx_vld,
    output wire                   rx_rdy,

    //------------------------------------------------------------------
    // Физические линии сброса счётчиков.
    // Длительность держит внешнее реле времени, которое на время работы
    // выставляет rst_busy.
    //------------------------------------------------------------------
    output logic                  soft_rst_req,
    output logic                  hard_rst_req,
    input  wire                   rst_busy,

    // Сами линии сброса. Машина обязана их видеть: сброс счётчиков —
    // это сброс общего состояния машины, а не только позиции разряда.
    // Инициатором может быть и кнопка на пульте, а не только инструкция.
    input  wire                   soft_rst,
    input  wire                   hard_rst,

    //------------------------------------------------------------------
    // Состояние машины
    //------------------------------------------------------------------
    output logic                  insn_mode,    // 0 = Debug ISA, 1 = Brainfuck ISA
    output wire                   is_halted,
    output logic                  bell,
    output logic [3:0]            state,
    output logic [31:0]           iret          // счётчик инструкций, только эмулятор
);

    //------------------------------------------------------------------
    // Состояния
    //
    // Коды S_HALT, S_IDLE, S_DECODE и S_CIN_WAIT прежние: по ним
    // DekatronPC_tb.cpp узнаёт окончание инструкции и ожидание ввода.
    //
    // S_IDLE, S_EXEC и S_CIN_WAIT выдают ровно одну операцию и покидают
    // себя в такте её приёма. Окончания операции ждут S_FETCH_W (выборка)
    // и общий S_WAIT (прочие операции); прежние пары OP/WAIT слиты.
    //------------------------------------------------------------------
    // Коды подобраны перебором по числу ламп: случайные назначения и их
    // мутации, отбор по пяти зёрнам &deepsyn; эти дают 317,7 лампы в
    // среднем против 324,6 у прежних 0,1,2,4,5,6,7,9,12,13
    // (doc/tube_count_reduction.md §17, T6). state выходит на пульт
    // (DPC_currentState), там коды не дешифруются. Тесты держат свои
    // копии: MachineCtrl_tb.sv, DekatronPC_tb.cpp, Emulator_tb.cpp,
    // rtl/run/cycle_profile.py.
    localparam logic [3:0]
        S_HALT      = 4'd4,
        S_IDLE      = 4'd0,   // запрос следующей инструкции
        S_FETCH_W   = 4'd1,   // ожидание выборки
        S_DECODE    = 4'd10,
        S_EXEC      = 4'd11,  // операция над IpLine или ApLine
        S_WAIT      = 4'd2,   // ожидание окончания операции
        S_COUT      = 4'd6,   // выдача символа в терминал после COUT или эхо
        S_CIN_WAIT  = 4'd15,  // ожидание символа с терминала
        S_RST_REQ   = 4'd14,  // запрос физического сброса
        S_RST_WAIT  = 4'd7;

    logic one_step;      // выполняется ровно одна инструкция
    logic [INSN_WIDTH-1:0] op_q;   // код текущей инструкции (op_load)
    logic pf_q;          // следующая инструкция выбрана заранее
    logic overflow_q;    // переполнение вложенности уже обработано
    logic rst_soft;      // сброс программный (иначе аппаратный)

    //------------------------------------------------------------------
    // Признак, который проверяют скобки:
    // в Brainfuck ISA — ноль текущей ячейки, в Debug ISA — ноль адреса
    //------------------------------------------------------------------
    assign loop_val_zero = insn_mode ? data_zero : ap_zero;

    assign is_halted = (state == S_HALT);

    // Полный код инструкции с учётом текущего набора команд.
    // Память программ может читать следующую инструкцию, пока текущая
    // ещё исполняется, поэтому код дешифрируется только из op_q.
    // op_q пишется в S_FETCH_W (каждый такт, последний — уже с готовым
    // опкодом) и в последнем такте инструкции (op_end), когда на выходе
    // памяти уже заранее выбранная следующая. Если дальше не S_DECODE, а
    // S_IDLE или S_HALT, запись безвредна: S_FETCH_W перепишет op_q.
    // Набор команд меняется только в S_DECODE и при сбросе, так что
    // {insn_mode, op_q} держится до ready ApLine, как того требует
    // Valid/Ready.
    wire [4:0] op_cur = {insn_mode, op_q};

    assign ap_op = op_cur;

    wire is_cin     = (op_cur == 5'h19);
    wire is_cout    = (op_cur == 5'h18);
    wire is_ip_op   = (op_cur == 5'h08) | (op_cur == 5'h09);   // CLRL, CLRI
    // Скобка в S_EXEC — это TEST (только BF); в Debug скобки туда не
    // попадают, поэтому режим не проверяется
    wire is_bracket = (op_q[3:1] == 3'b011);

    //------------------------------------------------------------------
    // Готовность исполнителей.
    // Пока поднята линия сброса, ни одна операция не выдаётся: автомат
    // в следующем такте всё равно уйдёт в S_RST_WAIT.
    //------------------------------------------------------------------
    wire rst_line = soft_rst | hard_rst;
    wire go       = ip_ready & ap_ready & ~rst_line;

    // Переполнение счётчика вложенности — аппаратная ошибка. Промотка
    // прервана самим IpLine, парная скобка не найдена, продолжать
    // исполнение бессмысленно: машина останавливается (REQ-CTLV2-005).
    // Реакция на фронт: IpLine держит признак до CLRL или сброса, и
    // после пуска с пульта машина не должна останавливаться снова.
    wire overflow_hit = loop_overflow & ~overflow_q;

    //------------------------------------------------------------------
    // Стробы исполнителям — дешифрация состояния (автомат Мура)
    //
    // valid поднимается только при go, то есть при уже поднятом ready
    // исполнителя, и рукопожатие происходит в том же такте. ready
    // исполнителей от valid не зависят, петли нет.
    //------------------------------------------------------------------
    wire in_idle   = (state == S_IDLE);
    wire in_decode = (state == S_DECODE);
    wire in_exec   = (state == S_EXEC);
    wire in_wait   = (state == S_WAIT);
    wire in_cin    = (state == S_CIN_WAIT);
    wire in_rst_rq = (state == S_RST_REQ);

    // В S_EXEC линия выборки получает CLRL/CLRI либо, вместе с ap_valid,
    // упреждающую выборку: всё, кроме скобки (TEST)
    assign ip_valid = ((in_idle & ~halt_key) | (in_exec & ~is_bracket)) & go;
    assign ap_valid = ((in_exec & ~is_ip_op) | (in_cin & ~halt_key & rx_vld)) & go;

    // CLRL (0x8) и CLRI (0x9) IpLine различает по своему же опкоду:
    // при них упреждающей выборки нет, и insn ещё текущий
    assign ip_clr = in_exec & is_ip_op;

    assign ip_ahead = pf_q;

    // После операции — вывод символа (COUT или эхо после CIN)
    wire cout_echo = is_cout | (is_cin & echo_mode);

    // Последний такт инструкции, исполнявшейся через S_WAIT/S_COUT
    wire op_end  = (in_wait & go & ~cout_echo) | ((state == S_COUT) & tx_rdy);
    wire op_load = (state == S_FETCH_W) | op_end;

    assign tx_vld = (state == S_COUT);

    // Приём символа завершается, когда ApLine закончил CIN: до этого
    // момента счётчик данных пишется прямо с rx_data_bcd, и передающая
    // сторона обязана держать его (REQ-UART-008). От rx_vld не зависит.
    assign rx_rdy = in_wait & is_cin & go;

    // Запрос держится, пока реле времени не подхватит его
    assign soft_rst_req = in_rst_rq &  rst_soft;
    assign hard_rst_req = in_rst_rq & ~rst_soft;

    // Звонок — импульс в такт события
    wire decode_run = in_decode & ~insn_loading;

    // Тумблеры звонка — контакты реле, а не лампы (rtl/Logic/Relay.sv)
    wire bell_halt, bell_cin, bell_error;
    RelayEn #(.W(1)) u_bell_halt (
        .en (bell_on_halt),
        .a  ((in_idle & halt_key) |
             (decode_run & ((op_cur == 5'h01) | (op_cur == 5'h11)))),
        .y  (bell_halt));
    RelayEn #(.W(1)) u_bell_cin (
        .en (bell_on_cin),
        .a  (decode_run & is_cin),
        .y  (bell_cin));
    RelayEn #(.W(1)) u_bell_error (
        .en (bell_on_error),
        .a  (overflow_hit),
        .y  (bell_error));

    assign bell = bell_halt |
                  (decode_run & (op_cur == 5'h02)) |                   // BELL
                  bell_cin |
                  bell_error;

    // Окончание инструкции: останов по кнопке или пошаговому режиму.
    // Если следующая инструкция уже выбрана, сразу её дешифрация: выход
    // в s_next бывает только по go, то есть выборка закончена
    wire [3:0] s_next = (halt_key | one_step) ? S_HALT
                      : pf_q                  ? S_DECODE
                      :                         S_IDLE;

    // Эхо (echo_mode) остаётся на лампах: is_cin & echo_mode сливается с
    // логикой перехода, реле лампу не экономит (doc/tube_count_reduction.md §15).

    // Пуск после сброса: rst_soft ? run_on_soft_rst : run_on_hard_rst.
    // Реле управляют только тумблеры, поэтому rst_soft идёт через контакты:
    // {soft, hard} = 00 -> 0, 01 -> ~rst_soft, 10 -> rst_soft, 11 -> 1
    wire run_on_rst;
    RelayMux #(.W(1), .S(2)) u_run_on_rst (
        .sel ({run_on_soft_rst, run_on_hard_rst}),
        .d   ({1'b1, rst_soft, ~rst_soft, 1'b0}),
        .y   (run_on_rst));

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state        <= S_HALT;
            insn_mode    <= 1'b0;          // после включения — Debug ISA
            insn_loading <= 1'b0;
            one_step     <= 1'b0;
            overflow_q   <= 1'b0;
            rst_soft     <= 1'b0;
            op_q         <= '0;
            pf_q         <= 1'b0;
            iret         <= '0;
        end
        else begin
            overflow_q <= loop_overflow;

            if (op_load) op_q <= insn;

            // Общемашинный сброс по физическим линиям. Работает
            // одинаково и для сброса по инструкции, и для сброса с
            // пульта: линию в обоих случаях удерживает реле времени.
            if (rst_line) begin
                rst_soft     <= ~hard_rst;
                insn_loading <= 1'b0;
                one_step     <= 1'b0;
                pf_q         <= 1'b0;
                state        <= S_RST_WAIT;
            end
            // Переполнение вложенности перебивает любое состояние
            // (оно возникает в S_FETCH_W, где иначе началась бы
            // дешифрация скобки, на которой промотка прервана)
            else if (overflow_hit) begin
                state <= S_HALT;
            end
            else begin
            case (state)

            //--------------------------------------------------------------
            S_HALT: begin
                if (step_key | run_key | key_insn_loading_start) begin
                    if (key_insn_loading_start)
                        insn_loading <= 1'b1;

                    if (~one_step) begin
                        if (step_key) one_step <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                // Отпускание кнопки шага разрешает следующий шаг
                if (one_step & ~step_key)
                    one_step <= 1'b0;
            end

            //--------------------------------------------------------------
            // Запрос следующей инструкции.
            // Промотку тела цикла IpLine выполняет самостоятельно.
            //--------------------------------------------------------------
            S_IDLE: begin
                pf_q <= 1'b0;   // после останова выборка обычная
                if (halt_key)  state <= S_HALT;
                else if (go)   state <= S_FETCH_W;
            end

            S_FETCH_W: begin
                if (go & insn_valid) begin
                    // Загрузка программы прерывается кнопкой или остановом
                    if (insn_loading & (key_insn_loading_stop | halt_key)) begin
                        insn_loading <= 1'b0;
                        state        <= S_HALT;
                    end
                    else begin
                        state <= S_DECODE;
                    end
                end
            end

            //--------------------------------------------------------------
            // Декодирование
            //--------------------------------------------------------------
            S_DECODE: begin
                if (EN_EMULATOR) iret <= iret + 32'd1;
                pf_q <= 1'b0;

                if (insn_loading & insn_eot) begin
                    //------------------------------------------------------
                    // EOT — конец загрузки. В память он не пишется,
                    // поэтому приходит отдельным признаком, а не в insn
                    //------------------------------------------------------
                    insn_loading <= 1'b0;
                    if (soft_rst_on_eot) begin
                        rst_soft <= 1'b1;
                        state    <= S_RST_REQ;
                    end
                    else begin
                        state <= S_HALT;
                    end
                end
                else if (insn_loading) begin
                    //------------------------------------------------------
                    // Режим загрузки программы: исполняются только
                    // служебные коды, остальное просто пишется в память.
                    // insn — только что записанный опкод (сквозная запись)
                    //------------------------------------------------------
                    case (op_cur)
                        5'h0E, 5'h1E: begin             // ISA0
                            insn_mode <= 1'b0;
                            state     <= S_IDLE;
                        end
                        5'h0F, 5'h1F: begin             // ISA1
                            insn_mode <= 1'b1;
                            state     <= S_IDLE;
                        end
                        default: state <= S_IDLE;
                    endcase
                end
                else begin
                    //------------------------------------------------------
                    // Обычное исполнение. В S_EXEC операцией служит
                    // сама инструкция (ip_clr, ap_valid выше)
                    //------------------------------------------------------
                    case (op_cur)

                    //--- общие для обоих наборов ---------------------------
                    5'h01, 5'h11:                       // HALT
                        state <= S_HALT;

                    5'h0E, 5'h1E: begin                 // ISA0 — в Debug
                        insn_mode <= 1'b0;
                        state     <= one_step ? S_HALT : S_IDLE;
                    end

                    5'h0F, 5'h1F: begin                 // ISA1 — в Brainfuck
                        insn_mode <= 1'b1;
                        state     <= one_step ? S_HALT : S_IDLE;
                    end

                    //--- скобки -------------------------------------------
                    // Промотку делает IpLine, но решение он принимает по
                    // признаку loop_val_zero. При ленивом чтении значение
                    // ячейки может быть ещё не прочитано, поэтому сначала
                    // просим ApLine обеспечить достоверность признака.
                    // За одну проверку скобки — одно обращение к памяти,
                    // и то лишь если значение не под рукой; во время самой
                    // промотки проверка не повторяется.
                    // В Debug ISA скобки проверяют счётчик адреса, он
                    // достоверен всегда.
                    5'h16, 5'h17:                       // [ ]
                        state <= ~data_zero_valid ? S_EXEC
                               : one_step         ? S_HALT : S_IDLE;

                    //--- Debug ISA ----------------------------------------
                    5'h05: begin                        // SOT — начало загрузки
                        insn_loading <= 1'b1;
                        state        <= one_step ? S_HALT : S_IDLE;
                    end

                    5'h08, 5'h09,                       // CLRL, CLRI
                    5'h0A, 5'h0B:                       // CLRD, CLRA
                        state <= S_EXEC;

                    5'h0C: begin                        // HRST
                        rst_soft <= 1'b0;
                        state    <= S_RST_REQ;
                    end

                    5'h0D: begin                        // SRST
                        rst_soft <= 1'b1;
                        state    <= S_RST_REQ;
                    end

                    //--- Brainfuck ISA ------------------------------------
                    // '.' выводит счётчик данных: ApLine сначала
                    // загружает в него ячейку, если MemLock снят
                    5'h12, 5'h13,                       // + -
                    5'h14, 5'h15,                       // > <
                    5'h18,                              // . COUT
                    5'h1A, 5'h1B,                       // [-] CLRML
                    5'h1C, 5'h1D:                       // LOAD STORE
                        state <= S_EXEC;

                    5'h19:                              // , CIN
                        state <= S_CIN_WAIT;

                    //--- NOP, BELL, незанятые опкоды -----------------------
                    default:
                        state <= one_step ? S_HALT : S_IDLE;
                    endcase
                end
            end

            //--------------------------------------------------------------
            // Операция над счётчиками: выдача и ожидание окончания
            //--------------------------------------------------------------
            S_EXEC: begin
                if (go) begin
                    pf_q  <= ~is_bracket & ~is_ip_op;   // выдана и выборка
                    state <= S_WAIT;
                end
            end

            S_WAIT: begin
                // Вывод символа, в том числе эхо после ввода
                if (go) state <= cout_echo ? S_COUT : s_next;
            end

            //--------------------------------------------------------------
            // Ввод символа с терминала: ApLine пишет его в счётчик
            //--------------------------------------------------------------
            S_CIN_WAIT: begin
                if (halt_key)          state <= S_HALT;
                else if (rx_vld & go)  state <= S_WAIT;
            end

            //--------------------------------------------------------------
            // Вывод символа в терминал
            //--------------------------------------------------------------
            S_COUT: begin
                if (tx_rdy) state <= s_next;
            end

            //--------------------------------------------------------------
            // Физический сброс счётчиков
            //--------------------------------------------------------------
            S_RST_REQ: begin
                if (rst_busy) state <= S_RST_WAIT;
            end

            S_RST_WAIT: begin
                if (~rst_busy) begin
                    // Набор команд после сброса задан архитектурой:
                    // после аппаратного стартует загрузчик в Debug ISA,
                    // после программного — программа в Brainfuck ISA
                    insn_mode <= rst_soft;
                    state     <= run_on_rst ? S_IDLE : S_HALT;
                end
            end

            default: state <= S_IDLE;
            endcase

            end   // конец ветки «сброс не активен»
        end
    end

`ifndef SYNTH
`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && soft_rst_req && hard_rst_req)
            $error("MachineCtrl: одновременный запрос программного и аппаратного сброса");
        if (rst_n && ip_valid && ap_valid && ip_clr)
            $error("MachineCtrl: CLRL/CLRI одновременно с операцией ApLine");
        if (rst_n && ip_valid && !ip_clr && !insn_loading && insn_mode &&
            insn_valid && ((insn == 4'h6) || (insn == 4'h7)) && !data_zero_valid)
            $error("MachineCtrl: скобка обрабатывается при недостоверном признаке нуля");
        if (rst_n && insn_loading && ap_valid)
            $error("MachineCtrl: операция над данными во время загрузки программы");
        if (rst_n && overflow_hit)
            $error("MachineCtrl: переполнение счётчика вложенности циклов");
    end
`endif
`endif

endmodule

`default_nettype wire
