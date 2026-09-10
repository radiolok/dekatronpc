//======================================================================
// IpLine — блок выборки инструкций
//----------------------------------------------------------------------
// Содержит счётчик инструкций, счётчик глубины вложенности циклов и
// ведёт обмен с памятью программ по APB. Предоставляет вышестоящему
// блоку Valid/Ready.
//
//----------------------------------------------------------------------
// ПРОМОТКА ЦИКЛОВ
//
// Сумматора в машине нет, поэтому парную скобку приходится искать
// пошаговым перебором. Счётчик вложенности позволяет не сбиться на
// вложенных циклах:
//
//   старт: на своей скобке счётчик +1
//   шаг:   сдвинуть IP в сторону поиска, прочитать инструкцию
//          своя скобка   -> счётчик +1
//          ответная      -> счётчик -1
//          счётчик == 0  -> промотка завершена
//
// Промотка останавливается НА парной скобке, а не за ней. Дальше её
// обрабатывает обычная выборка: ']' при нулевой ячейке просто идёт
// дальше, '[' при ненулевой входит в тело.
//
// Счётчик вложенности самоочищается: к концу промотки он снова нуль.
//
//----------------------------------------------------------------------
// ПЕРВАЯ ВЫБОРКА ПОСЛЕ СБРОСА
//
// Сразу после сброса на выходе счётчика уже стоит нужный адрес, и
// инструкцию по нему надо прочитать БЕЗ инкремента. За это отвечает
// флаг ip_counted_q: пока он снят, очередная выборка не двигает IP.
//
//----------------------------------------------------------------------
// ЗАГРУЗКА ПРОГРАММЫ
//
// В режиме insn_loading блок принимает опкоды по insn_in_valid /
// insn_in_ready, пишет их в память по текущему адресу и продвигает IP.
// Приём EOT завершает загрузку.
//======================================================================

`include "../DekatronPC/insnValues.sv"

`default_nettype none

module IpLine #(
    // Сколько старших декад аппаратный сброс ставит в девятку.
    // Для пяти декатронов это даёт 99900 — начало загрузчика.
    parameter unsigned HARD_RST_D_CNT    = IP_DEKATRON_NUM - 2,

    // Чтение счётчика циклов нужно только для индикации в эмуляторе
    parameter bit          LOOP_READ         = 1'b0
)(
    input  wire rst_n,        // сброс логики; разряд декатронов не двигает
    input  wire clk,
    input  wire hs_clk,

    // Физические линии сброса счётчиков (удерживает реле времени)
    input  wire soft_rst,
    input  wire hard_rst,

    //------------------------------------------------------------------
    // Командный интерфейс
    //------------------------------------------------------------------
    input  wire       valid,
    output wire       ready,
    input  wire [1:0] op,

    // Состояние проверяемой циклом величины. В Brainfuck ISA это признак
    // нуля текущей ячейки, в Debug ISA — признак нуля счётчика адреса.
    // Выбор делает блок управления, сюда приходит уже готовый признак.
    input  wire       loop_val_zero,

    //------------------------------------------------------------------
    // Выборка
    //------------------------------------------------------------------
    output wire [INSN_WIDTH-1:0] insn,
    output wire                  insn_valid,

    //------------------------------------------------------------------
    // Останов и ручное перемещение по программе
    //------------------------------------------------------------------
    input  wire halt_rq,
    input  wire key_prev_ip,
    input  wire key_next_ip,

    //------------------------------------------------------------------
    // Загрузка программы
    //------------------------------------------------------------------
    input  wire                  insn_loading,
    input  wire                  insn_mode,
    input  wire [INSN_WIDTH-1:0] insn_in,
    input  wire                  insn_in_valid,
    output wire                  insn_in_ready,

    //------------------------------------------------------------------
    // Состояние для блока управления и индикации
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ip_addr,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] loop_count,
    output wire                                        loop_overflow,

    //------------------------------------------------------------------
    // Память программ, APB
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] mem_addr,
    output wire [INSN_WIDTH-1:0]                     mem_wr_data,
    input  wire [INSN_WIDTH-1:0]                     mem_rd_data,
    output logic                                     mem_valid,
    input  wire                                      mem_ready,
    output logic                                     mem_wr,
    input  wire                                      mem_rd_valid,
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                                      mem_err
/* verilator lint_on UNUSEDSIGNAL */
);

    localparam int unsigned IP_W   = IP_DEKATRON_NUM   * DEKATRON_WIDTH;
    localparam int unsigned LOOP_W = LOOP_DEKATRON_NUM * DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Коды операций
    //------------------------------------------------------------------
    localparam logic [1:0]
        OP_NEXT     = 2'd0,   // выдать следующую инструкцию
        OP_CLR_IP   = 2'd1,   // CLRI — счётчик инструкций в нуль
        OP_CLR_LOOP = 2'd2;   // CLRL — счётчик циклов в нуль

    //------------------------------------------------------------------
    // Состояния
    //------------------------------------------------------------------
    localparam logic [3:0]
        S_IDLE        = 4'd0,
        S_IP_OP       = 4'd1,   // шаг счётчика инструкций
        S_IP_WAIT     = 4'd2,
        S_FETCH       = 4'd3,   // чтение инструкции из памяти
        S_SCAN_EVAL   = 4'd5,   // разбор прочитанной скобки
        S_LOOP_OP     = 4'd6,   // шаг счётчика вложенности
        S_LOOP_WAIT   = 4'd7,
        S_INSN_IN     = 4'd8,   // приём опкода при загрузке
        S_WRITE       = 4'd9,   // запись опкода в память
        S_CLR_OP      = 4'd11,  // сброс одного из счётчиков
        S_CLR_WAIT    = 4'd12,
        S_HALT        = 4'd13;

    logic [3:0] state;

    logic                  ip_counted_q;   // IP уже сдвинут под текущую инструкцию
    logic                  scanning_q;     // идёт промотка тела цикла
    logic                  scan_dec_q;     // направление промотки: 1 — назад
    logic                  loop_init_q;    // текущий шаг счётчика циклов — стартовый
    logic                  key_moved_q;    // ручной шаг уже сделан, ждём отпускания
    logic                  halt_pending_q;
    logic                  clr_is_loop_q;  // сбрасываем счётчик циклов, а не IP
    logic                  overflow_q;
    logic [INSN_WIDTH-1:0] insn_q;
    logic                  insn_valid_q;
    logic [INSN_WIDTH-1:0] insn_in_q;

    //------------------------------------------------------------------
    // Счётчик инструкций
    //------------------------------------------------------------------
    logic           ip_valid;
    wire            ip_ready;
    logic           ip_dec;
    logic           ip_set_zero;
    wire [IP_W-1:0] ip_out;
    wire            ip_out_valid;

    DekatronCounter #(
        .D_NUM          (IP_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b0),
        .TOP_LIMIT_MODE (1'b0),
        .HARD_RST_D_CNT (HARD_RST_D_CNT)
    ) ip_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (ip_valid),
        .ready     (ip_ready),
        .dec       (ip_dec),
        .set       (1'b0),
        .set_zero  (ip_set_zero),
        .in        ({IP_W{1'b0}}),
        .out       (ip_out),
        .out_valid (ip_out_valid),
        .zero      (),
        .at_top    ()
    );

    assign ip_addr  = ip_out;
    assign mem_addr = ip_out;

    //------------------------------------------------------------------
    // Счётчик глубины вложенности циклов
    //------------------------------------------------------------------
    logic             loop_valid;
    wire              loop_ready;
    logic             loop_dec;
    logic             loop_set_zero;
    wire [LOOP_W-1:0] loop_out;
    wire              loop_out_valid;
    wire              loop_is_zero;

    DekatronCounter #(
        .D_NUM          (LOOP_DEKATRON_NUM),
        .READ           (LOOP_READ),
        .WRITE          (1'b0),
        .TOP_LIMIT_MODE (1'b0),
        .HARD_RST_D_CNT (0)
    ) loop_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (loop_valid),
        .ready     (loop_ready),
        .dec       (loop_dec),
        .set       (1'b0),
        .set_zero  (loop_set_zero),
        .in        ({LOOP_W{1'b0}}),
        .out       (loop_out),
        .out_valid (loop_out_valid),
        .zero      (loop_is_zero),
        .at_top    ()
    );

    assign loop_count    = loop_out;
    assign loop_overflow = overflow_q;

    //------------------------------------------------------------------
    // Распознавание скобок
    //
    // Детектор один: он разбирает регистр insn_q, а тот в разные моменты
    // держит либо текущую инструкцию (решение о начале промотки), либо
    // только что прочитанную в ходе промотки. Опкоды скобок одинаковы в
    // обоих наборах команд, поэтому режим ISA здесь не нужен.
    //------------------------------------------------------------------
    wire insn_loop_open, insn_loop_close;

    InsnLoopDetector loopDetector (
        .Insn      (insn_q),
        .LoopOpen  (insn_loop_open),
        .LoopClose (insn_loop_close)
    );

    // Условия начала промотки
    wire scan_fwd_req  = insn_loop_open  &  loop_val_zero;   // '[' и ноль
    wire scan_back_req = insn_loop_close & ~loop_val_zero;   // ']' и не ноль
    wire scan_req      = scan_fwd_req | scan_back_req;

    //------------------------------------------------------------------
    // APB-мастер
    //------------------------------------------------------------------
    assign mem_wr_data = insn_in_q;

    //------------------------------------------------------------------
    // Выходы и готовность
    //------------------------------------------------------------------
    assign insn          = insn_q;
    assign insn_valid    = insn_valid_q;
    assign insn_in_ready = (state == S_INSN_IN);

    assign ready = (state == S_IDLE) & ~halt_rq &
                   ip_ready & loop_ready & mem_ready;

    wire accept = valid & ready;

    wire end_of_transmission = ({insn_mode, insn_in} == INSN_EOT);

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state          <= S_IDLE;
            ip_counted_q   <= 1'b0;
            scanning_q     <= 1'b0;
            scan_dec_q     <= 1'b0;
            loop_init_q    <= 1'b0;
            key_moved_q    <= 1'b0;
            halt_pending_q <= 1'b0;
            clr_is_loop_q  <= 1'b0;
            overflow_q     <= 1'b0;
            insn_q         <= '0;
            insn_valid_q   <= 1'b0;
            insn_in_q      <= '0;
            ip_valid       <= 1'b0;
            ip_dec         <= 1'b0;
            ip_set_zero    <= 1'b0;
            loop_valid     <= 1'b0;
            loop_dec       <= 1'b0;
            loop_set_zero  <= 1'b0;
            mem_valid      <= 1'b0;
            mem_wr         <= 1'b0;
        end
        else begin
            ip_valid   <= 1'b0;
            loop_valid <= 1'b0;
            mem_valid  <= 1'b0;

            // Физический сброс счётчиков обнуляет и состояние выборки:
            // адрес ушёл на начало, прочитанная инструкция недостоверна
            if (soft_rst | hard_rst) begin
                state         <= S_IDLE;
                ip_counted_q  <= 1'b0;
                scanning_q    <= 1'b0;
                insn_valid_q  <= 1'b0;
                overflow_q    <= 1'b0;
                ip_set_zero   <= 1'b0;
                loop_set_zero <= 1'b0;
                mem_wr        <= 1'b0;
            end
            else begin
                case (state)

                //------------------------------------------------------
                S_IDLE: begin
                    if (halt_rq) begin
                        // При останове продвигаем IP на следующую
                        // инструкцию и снимаем признак выборки, чтобы
                        // после возобновления читать заново
                        if (ip_counted_q) begin
                            ip_counted_q   <= 1'b0;
                            halt_pending_q <= 1'b1;
                            ip_dec         <= 1'b0;
                            ip_valid       <= 1'b1;
                            state          <= S_IP_OP;
                        end
                        else begin
                            state <= S_HALT;
                        end
                    end
                    else if (accept) begin
                        case (op)

                        OP_CLR_IP: begin
                            clr_is_loop_q <= 1'b0;
                            ip_set_zero   <= 1'b1;
                            ip_valid      <= 1'b1;
                            ip_counted_q  <= 1'b0;
                            insn_valid_q  <= 1'b0;
                            state         <= S_CLR_OP;
                        end

                        OP_CLR_LOOP: begin
                            clr_is_loop_q <= 1'b1;
                            loop_set_zero <= 1'b1;
                            loop_valid    <= 1'b1;
                            overflow_q    <= 1'b0;
                            state         <= S_CLR_OP;
                        end

                        default: begin   // OP_NEXT
                            if (~ip_counted_q) begin
                                // Первая выборка после сброса: читаем по
                                // текущему адресу, счётчик не двигаем
                                ip_counted_q <= 1'b1;
                                if (insn_loading) state <= S_INSN_IN;
                                else              begin mem_valid <= 1'b1; mem_wr <= 1'b0; state <= S_FETCH; end
                            end
                            else if (insn_loading) begin
                                ip_dec   <= 1'b0;
                                ip_valid <= 1'b1;
                                state    <= S_IP_OP;
                            end
                            else if (scan_req) begin
                                // Начало промотки: своя скобка учитывается
                                // в счётчике вложенности
                                scanning_q  <= 1'b1;
                                scan_dec_q  <= scan_back_req;
                                loop_init_q <= 1'b1;
                                loop_dec    <= 1'b0;
                                loop_valid  <= 1'b1;
                                state       <= S_LOOP_OP;
                            end
                            else begin
                                ip_dec   <= 1'b0;
                                ip_valid <= 1'b1;
                                state    <= S_IP_OP;
                            end
                        end
                        endcase
                    end
                end

                //------------------------------------------------------
                // Шаг счётчика инструкций
                //------------------------------------------------------
                S_IP_OP: begin
                    if (ip_ready) state <= S_IP_WAIT;
                    else          ip_valid <= 1'b1;
                end

                S_IP_WAIT: begin
                    if (ip_ready & ip_out_valid) begin
                        if (halt_pending_q) begin
                            halt_pending_q <= 1'b0;
                            insn_valid_q   <= 1'b0;
                            state          <= S_HALT;
                        end
                        else if (insn_loading & ~scanning_q) begin
                            state <= S_INSN_IN;
                        end
                        else begin
                            begin mem_valid <= 1'b1; mem_wr <= 1'b0; state <= S_FETCH; end
                        end
                    end
                end

                //------------------------------------------------------
                // Чтение инструкции
                //------------------------------------------------------
                S_FETCH: begin
                    if (mem_ready & mem_rd_valid) begin
                        insn_q       <= mem_rd_data;
                        insn_valid_q <= 1'b1;
                        if (scanning_q) state <= S_SCAN_EVAL;
                        else            state <= S_IDLE;
                    end
                    else if (mem_ready) begin
                        mem_valid <= 1'b1;    // удерживаем до приёма
                        mem_wr    <= 1'b0;
                    end
                end

                //------------------------------------------------------
                // Разбор прочитанной инструкции в ходе промотки
                //------------------------------------------------------
                S_SCAN_EVAL: begin
                    if (insn_loop_open | insn_loop_close) begin
                        // Своя скобка углубляет вложенность, ответная
                        // поднимает: направление зависит от того, куда
                        // идёт промотка
                        loop_init_q <= 1'b0;
                        loop_dec    <= scan_dec_q ? insn_loop_open
                                                  : insn_loop_close;
                        loop_valid  <= 1'b1;
                        state       <= S_LOOP_OP;
                    end
                    else begin
                        // Обычная инструкция: шагаем дальше
                        ip_dec   <= scan_dec_q;
                        ip_valid <= 1'b1;
                        state    <= S_IP_OP;
                    end
                end

                //------------------------------------------------------
                // Шаг счётчика вложенности
                //------------------------------------------------------
                S_LOOP_OP: begin
                    if (loop_ready) state <= S_LOOP_WAIT;
                    else            loop_valid <= 1'b1;
                end

                S_LOOP_WAIT: begin
                    if (loop_ready & loop_out_valid) begin
                        // Обнуление счётчика при инкременте означает, что
                        // он перевалил через 999 — глубина вложенности
                        // превысила возможности машины
                        if (~loop_dec & loop_is_zero) begin
                            // Промотку обязательно прервать: парная скобка
                            // уже не найдётся, и машина зависла бы в
                            // бесконечном переборе адресов
                            overflow_q <= 1'b1;
                            scanning_q <= 1'b0;
                            state      <= S_IDLE;
                        end
                        else if (~loop_init_q & loop_dec & loop_is_zero) begin
                            // Парная скобка найдена, стоим на ней
                            scanning_q <= 1'b0;
                            state      <= S_IDLE;
                        end
                        else begin
                            ip_dec   <= scan_dec_q;
                            ip_valid <= 1'b1;
                            state    <= S_IP_OP;
                        end
                    end
                end

                //------------------------------------------------------
                // Приём опкода при загрузке программы
                //------------------------------------------------------
                S_INSN_IN: begin
                    if (insn_in_valid) begin
                        insn_in_q    <= insn_in;
                        insn_q       <= insn_in;
                        insn_valid_q <= 1'b1;

                        if (end_of_transmission | ~insn_loading) begin
                            state <= S_IDLE;      // загрузка завершена
                        end
                        else begin
                            mem_valid <= 1'b1;
                            mem_wr    <= 1'b1;
                            state     <= S_WRITE;
                        end
                    end
                    else if (~insn_loading) begin
                        state <= S_IDLE;
                    end
                    else if ((key_prev_ip | key_next_ip) & ~key_moved_q) begin
                        // Ручное перемещение по программе во время загрузки
                        key_moved_q <= 1'b1;
                        ip_dec      <= key_prev_ip;
                        ip_valid    <= 1'b1;
                        state       <= S_IP_OP;
                    end
                    else if (~key_prev_ip & ~key_next_ip) begin
                        key_moved_q <= 1'b0;
                    end
                end

                //------------------------------------------------------
                // Запись опкода в память
                //------------------------------------------------------
                S_WRITE: begin
                    if (mem_ready & mem_rd_valid) begin
                        mem_wr <= 1'b0;
                        state  <= S_IDLE;
                    end
                    else if (mem_ready) begin
                        mem_valid <= 1'b1;
                        mem_wr    <= 1'b1;
                    end
                end

                //------------------------------------------------------
                // Сброс счётчика по команде
                //------------------------------------------------------
                S_CLR_OP: begin
                    if (clr_is_loop_q) begin
                        if (loop_ready) begin
                            loop_set_zero <= 1'b0;
                            state         <= S_CLR_WAIT;
                        end
                        else loop_valid <= 1'b1;
                    end
                    else begin
                        if (ip_ready) begin
                            ip_set_zero <= 1'b0;
                            state       <= S_CLR_WAIT;
                        end
                        else ip_valid <= 1'b1;
                    end
                end

                S_CLR_WAIT: begin
                    if (clr_is_loop_q) begin
                        if (loop_ready & loop_out_valid) state <= S_IDLE;
                    end
                    else begin
                        if (ip_ready & ip_out_valid) state <= S_IDLE;
                    end
                end

                //------------------------------------------------------
                // Останов с возможностью ручного перемещения
                //------------------------------------------------------
                S_HALT: begin
                    if (~halt_rq) begin
                        state <= S_IDLE;
                    end
                    else if ((key_prev_ip | key_next_ip) & ~key_moved_q) begin
                        key_moved_q <= 1'b1;
                        ip_dec      <= key_prev_ip;
                        ip_valid    <= 1'b1;
                        state       <= S_IP_OP;
                        // После ручного шага инструкция читается заново
                        halt_pending_q <= 1'b1;
                    end
                    else if (~key_prev_ip & ~key_next_ip) begin
                        key_moved_q <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTH
`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && valid && (op > OP_CLR_LOOP))
            $error("IpLine: неизвестный код операции %0d", op);
        if (rst_n && $past(valid) && !$past(ready) && !valid)
            $error("IpLine: valid снят до handshake");
        if (rst_n && mem_err)
            $error("IpLine: ошибка обращения к памяти программ");
        if (rst_n && overflow_q && !$past(overflow_q))
            $error("IpLine: переполнение счётчика вложенности циклов");
        // Одновременная работа обоих счётчиков не предусмотрена
        if (rst_n && ip_valid && loop_valid)
            $error("IpLine: одновременный запрос к обоим счётчикам");
    end
`endif
`endif

endmodule

`default_nettype wire
