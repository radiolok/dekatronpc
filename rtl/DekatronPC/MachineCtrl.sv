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
//    перед скобкой декодер просит ApLine его обеспечить операцией
//    AP_TEST. Это одно обращение к памяти на проверку скобки и только
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
//    линии. Заменено на два интерфейса Valid/Ready с кодом операции.
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
    output logic [1:0]            ip_op,
    output wire                   loop_val_zero,
    output logic                  insn_loading,
    input  wire [INSN_WIDTH-1:0]  insn,
    input  wire                   insn_valid,
    input  wire                   loop_overflow,

    //------------------------------------------------------------------
    // Линия работы с данными
    //------------------------------------------------------------------
    output logic                  ap_valid,
    input  wire                   ap_ready,
    output logic [3:0]            ap_op,
    output logic                  ap_dec,
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
    // Коды операций подчинённых блоков
    //------------------------------------------------------------------
    localparam logic [1:0]
        IP_NEXT     = 2'd0,
        IP_CLR_IP   = 2'd1,
        IP_CLR_LOOP = 2'd2;

    localparam logic [3:0]
        AP_NOP       = 4'd0,
        AP_AP_STEP   = 4'd1,
        AP_AP_ZERO   = 4'd2,
        AP_DATA_STEP = 4'd3,
        AP_DATA_ZERO = 4'd4,
        AP_CIN       = 4'd5,
        AP_COUT      = 4'd6,
        AP_LOAD      = 4'd7,
        AP_STORE     = 4'd8,
        AP_CLRML     = 4'd9,
        AP_TEST      = 4'd10;

    //------------------------------------------------------------------
    // Состояния
    //------------------------------------------------------------------
    localparam logic [3:0]
        S_HALT      = 4'd0,
        S_IDLE      = 4'd1,
        S_FETCH     = 4'd2,   // запрос следующей инструкции
        S_FETCH_W   = 4'd3,
        S_DECODE    = 4'd4,
        S_IP_OP     = 4'd5,   // сброс счётчика IP или циклов
        S_IP_OP_W   = 4'd6,
        S_AP_OP     = 4'd7,   // операция над данными или адресом
        S_AP_OP_W   = 4'd8,
        S_CIN_WAIT  = 4'd9,   // ожидание символа с терминала
        S_COUT      = 4'd10,  // выдача символа в терминал
        S_ECHO      = 4'd11,
        S_RST_REQ   = 4'd12,  // запрос физического сброса
        S_RST_WAIT  = 4'd13,
        S_BELL      = 4'd14;

    localparam logic [1:0]
        RST_NONE = 2'd0,
        RST_HARD = 2'd1,
        RST_SOFT = 2'd2;

    logic [1:0] rst_type;
    logic       one_step;      // выполняется ровно одна инструкция
    logic       echo_pending;
    logic       bell_pending;
    logic       error_flag;

    //------------------------------------------------------------------
    // Признак, который проверяют скобки:
    // в Brainfuck ISA — ноль текущей ячейки, в Debug ISA — ноль адреса
    //------------------------------------------------------------------
    assign loop_val_zero = insn_mode ? data_zero : ap_zero;

    assign is_halted = (state == S_HALT);

    wire run_on_rst = ((rst_type == RST_HARD) & run_on_hard_rst) |
                      ((rst_type == RST_SOFT) & run_on_soft_rst);

    // Полный код инструкции с учётом текущего набора команд
    wire [4:0] op_full = {insn_mode, insn};

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state        <= S_HALT;
            insn_mode    <= 1'b0;          // после включения — Debug ISA
            insn_loading <= 1'b0;
            ip_valid     <= 1'b0;
            ip_op        <= IP_NEXT;
            ap_valid     <= 1'b0;
            ap_op        <= AP_NOP;
            ap_dec       <= 1'b0;
            tx_vld       <= 1'b0;
            soft_rst_req <= 1'b0;
            hard_rst_req <= 1'b0;
            rst_type     <= RST_HARD;
            one_step     <= 1'b0;
            echo_pending <= 1'b0;
            bell_pending <= 1'b0;
            bell         <= 1'b0;
            error_flag   <= 1'b0;
            iret         <= '0;
        end
        else begin
            // Запросы по умолчанию сняты
            ip_valid <= 1'b0;
            ap_valid <= 1'b0;
            bell     <= 1'b0;

            // Общемашинный сброс по физическим линиям. Работает
            // одинаково и для сброса по инструкции, и для сброса с
            // пульта: линию в обоих случаях удерживает реле времени.
            if (soft_rst | hard_rst) begin
                rst_type     <= hard_rst ? RST_HARD : RST_SOFT;
                soft_rst_req <= 1'b0;
                hard_rst_req <= 1'b0;
                insn_loading <= 1'b0;
                one_step     <= 1'b0;
                echo_pending <= 1'b0;
                error_flag   <= 1'b0;
                tx_vld       <= 1'b0;
                state        <= S_RST_WAIT;
            end
            else begin

            // Переполнение счётчика вложенности — аппаратная ошибка.
            // Промотка при этом прервана самим IpLine, парная скобка не
            // найдена, поэтому продолжать исполнение бессмысленно:
            // машина останавливается.
            if (loop_overflow && !error_flag) begin
                error_flag <= 1'b1;
                if (bell_on_error) bell_pending <= 1'b1;
                state <= S_HALT;
            end

            case (state)

            //--------------------------------------------------------------
            S_HALT: begin
                if (bell_pending) begin
                    bell_pending <= 1'b0;
                    bell         <= 1'b1;
                end

                if (step_key | run_key | run_on_rst | key_insn_loading_start) begin
                    if (key_insn_loading_start)
                        insn_loading <= 1'b1;

                    if (~one_step) begin
                        rst_type <= RST_NONE;
                        if (step_key) one_step <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                // Отпускание кнопки шага разрешает следующий шаг
                if (one_step & ~step_key)
                    one_step <= 1'b0;
            end

            //--------------------------------------------------------------
            S_IDLE: begin
                if (halt_key) begin
                    if (bell_on_halt) bell_pending <= 1'b1;
                    state <= S_HALT;
                end
                else begin
                    ip_op    <= IP_NEXT;
                    ip_valid <= 1'b1;
                    state    <= S_FETCH;
                end
            end

            //--------------------------------------------------------------
            // Выборка очередной инструкции.
            // Промотку тела цикла IpLine выполняет самостоятельно.
            //--------------------------------------------------------------
            S_FETCH: begin
                if (ip_ready) state <= S_FETCH_W;
                else          ip_valid <= 1'b1;
            end

            S_FETCH_W: begin
                if (ip_ready & insn_valid) begin
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

                if (insn_loading) begin
                    //------------------------------------------------------
                    // Режим загрузки программы: исполняются только
                    // служебные коды, остальное просто пишется в память
                    //------------------------------------------------------
                    case (op_full)
                        5'h04: begin                    // EOT — конец загрузки
                            insn_loading <= 1'b0;
                            if (soft_rst_on_eot) begin
                                rst_type     <= RST_SOFT;
                                soft_rst_req <= 1'b1;
                                state        <= S_RST_REQ;
                            end
                            else begin
                                state <= S_HALT;
                            end
                        end
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
                    // Обычное исполнение
                    //------------------------------------------------------
                    case (op_full)

                    //--- общие для обоих наборов ---------------------------
                    5'h00, 5'h10: begin                 // NOP
                        state <= one_step ? S_HALT : S_IDLE;
                    end

                    5'h01, 5'h11: begin                 // HALT
                        if (bell_on_halt) bell_pending <= 1'b1;
                        state <= S_HALT;
                    end

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
                    5'h06, 5'h16,                       // [ {
                    5'h07, 5'h17: begin                 // ] }
                        if (insn_mode & ~data_zero_valid) begin
                            ap_op    <= AP_TEST;
                            ap_valid <= 1'b1;
                            state    <= S_AP_OP;
                        end
                        else begin
                            // В Debug ISA скобки проверяют счётчик адреса,
                            // он достоверен всегда
                            state <= one_step ? S_HALT : S_IDLE;
                        end
                    end

                    //--- Debug ISA ----------------------------------------
                    5'h02: begin                        // BELL
                        bell  <= 1'b1;
                        state <= one_step ? S_HALT : S_IDLE;
                    end

                    5'h05: begin                        // SOT — начало загрузки
                        insn_loading <= 1'b1;
                        state        <= one_step ? S_HALT : S_IDLE;
                    end

                    5'h08: begin                        // CLRL — счётчик циклов
                        ip_op      <= IP_CLR_LOOP;
                        ip_valid   <= 1'b1;
                        error_flag <= 1'b0;
                        state      <= S_IP_OP;
                    end

                    5'h09: begin                        // CLRI — счётчик инструкций
                        ip_op    <= IP_CLR_IP;
                        ip_valid <= 1'b1;
                        state    <= S_IP_OP;
                    end

                    5'h0A: begin                        // CLRD — обнулить ячейку
                        ap_op    <= AP_DATA_ZERO;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h0B: begin                        // CLRA — счётчик адреса
                        ap_op    <= AP_AP_ZERO;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h0C: begin                        // HRST
                        rst_type     <= RST_HARD;
                        hard_rst_req <= 1'b1;
                        state        <= S_RST_REQ;
                    end

                    5'h0D: begin                        // SRST
                        rst_type     <= RST_SOFT;
                        soft_rst_req <= 1'b1;
                        state        <= S_RST_REQ;
                    end

                    //--- Brainfuck ISA ------------------------------------
                    5'h12, 5'h13: begin                 // + -
                        ap_op    <= AP_DATA_STEP;
                        ap_dec   <= insn[0];
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h14, 5'h15: begin                 // > <
                        ap_op    <= AP_AP_STEP;
                        ap_dec   <= insn[0];
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h18: begin                        // . COUT
                        tx_vld <= 1'b1;
                        state  <= S_COUT;
                    end

                    5'h19: begin                        // , CIN
                        if (bell_on_cin) bell <= 1'b1;
                        state <= S_CIN_WAIT;
                    end

                    5'h1A: begin                        // [-] CLRD
                        ap_op    <= AP_DATA_ZERO;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h1B: begin                        // CLRML
                        ap_op    <= AP_CLRML;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h1C: begin                        // LOAD
                        ap_op    <= AP_LOAD;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    5'h1D: begin                        // STORE
                        ap_op    <= AP_STORE;
                        ap_valid <= 1'b1;
                        state    <= S_AP_OP;
                    end

                    //--- незанятые опкоды ведут себя как NOP --------------
                    default: begin
                        state <= one_step ? S_HALT : S_IDLE;
                    end
                    endcase
                end
            end

            //--------------------------------------------------------------
            // Операция над счётчиками линии выборки
            //--------------------------------------------------------------
            S_IP_OP: begin
                if (ip_ready) state <= S_IP_OP_W;
                else          ip_valid <= 1'b1;
            end

            S_IP_OP_W: begin
                if (ip_ready)
                    state <= (halt_key | one_step) ? S_HALT : S_IDLE;
            end

            //--------------------------------------------------------------
            // Операция над данными или адресом
            //--------------------------------------------------------------
            S_AP_OP: begin
                if (ap_ready) state <= S_AP_OP_W;
                else          ap_valid <= 1'b1;
            end

            S_AP_OP_W: begin
                if (ap_ready) begin
                    if (echo_pending) begin
                        // После ввода символа возвращаем его в терминал
                        echo_pending <= 1'b0;
                        tx_vld       <= 1'b1;
                        state        <= S_ECHO;
                    end
                    else begin
                        state <= (halt_key | one_step) ? S_HALT : S_IDLE;
                    end
                end
            end

            //--------------------------------------------------------------
            // Ввод символа с терминала
            //--------------------------------------------------------------
            S_CIN_WAIT: begin
                if (halt_key) begin
                    state <= S_HALT;
                end
                else if (rx_vld) begin
                    ap_op        <= AP_CIN;
                    ap_valid     <= 1'b1;
                    echo_pending <= echo_mode;
                    state        <= S_AP_OP;
                end
            end

            //--------------------------------------------------------------
            // Вывод символа в терминал
            //--------------------------------------------------------------
            S_COUT: begin
                if (tx_rdy) begin
                    tx_vld <= 1'b0;
                    state  <= (halt_key | one_step) ? S_HALT : S_IDLE;
                end
                else begin
                    tx_vld <= 1'b1;
                end
            end

            S_ECHO: begin
                if (tx_rdy) begin
                    tx_vld <= 1'b0;
                    state  <= (halt_key | one_step) ? S_HALT : S_IDLE;
                end
                else begin
                    tx_vld <= 1'b1;
                end
            end

            //--------------------------------------------------------------
            // Физический сброс счётчиков.
            // Запрос держится, пока реле времени не подхватит его.
            //--------------------------------------------------------------
            S_RST_REQ: begin
                if (rst_busy) begin
                    soft_rst_req <= 1'b0;
                    hard_rst_req <= 1'b0;
                    state        <= S_RST_WAIT;
                end
                else begin
                    soft_rst_req <= (rst_type == RST_SOFT);
                    hard_rst_req <= (rst_type == RST_HARD);
                end
            end

            S_RST_WAIT: begin
                if (~rst_busy) begin
                    // Набор команд после сброса задан архитектурой:
                    // после аппаратного стартует загрузчик в Debug ISA,
                    // после программного — программа в Brainfuck ISA
                    insn_mode <= (rst_type == RST_SOFT);
                    state     <= S_HALT;
                end
            end

            //--------------------------------------------------------------
            S_BELL: begin
                bell  <= 1'b1;
                state <= one_step ? S_HALT : S_IDLE;
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
        if (rst_n && ip_valid && ap_valid)
            $error("MachineCtrl: одновременный запрос к IpLine и ApLine");
        if (rst_n && !insn_loading && insn_mode &&
            ((insn == 4'h6) || (insn == 4'h7)) &&
            (state == S_FETCH_W) && ip_ready && insn_valid &&
            !data_zero_valid && !ap_valid)
            $error("MachineCtrl: скобка обрабатывается при недостоверном признаке нуля");
        if (rst_n && insn_loading && ap_valid)
            $error("MachineCtrl: операция над данными во время загрузки программы");
        if (rst_n && loop_overflow && !$past(loop_overflow))
            $error("MachineCtrl: переполнение счётчика вложенности циклов");
    end
`endif
`endif

endmodule

`default_nettype wire
