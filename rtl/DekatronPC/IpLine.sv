//======================================================================
// IpLine — блок выборки инструкций
//----------------------------------------------------------------------
// Содержит счётчик инструкций, счётчик глубины вложенности циклов и
// ведёт обмен с памятью программ по Valid/Ready. Предоставляет
// вышестоящему блоку Valid/Ready.
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
// Опкод уходит в память в такте рукопожатия, поэтому insn_in_ready
// поднимается только при свободной памяти. Приём EOT завершает
// загрузку; в память он не пишется.
//
//----------------------------------------------------------------------
// ОПКОД ДЕРЖИТ ПАМЯТЬ
//
// Собственного регистра опкода у блока нет (REQ-IPV2-008). Выходной
// регистр памяти программ меняется только при обращении и держит
// последнюю прочитанную или записанную (сквозная запись) инструкцию.
// Шаг IP, CLRI и останов к памяти не обращаются, а следующее обращение
// бывает лишь после того, как блок управления закончил с текущей
// инструкцией. Поэтому insn — это прямо mem_rd_data.
//
// Единственный опкод, которого в памяти нет, — EOT. О нём сообщает
// отдельный триггер insn_eot.
//
// При упреждающей выборке (P3) следующее обращение выдаётся вместе с
// операцией над ApLine. Опкод текущей инструкции к этому моменту
// защёлкнут в блоке управления, а решение о промотке блок принимает в
// такте приёма запроса, пока insn ещё текущий.
//
//----------------------------------------------------------------------
// ОСТАНОВ
//
// Обычно IP стоит на исполненной инструкции, и при останове блок
// сдвигает его на следующую. Если же следующая уже выбрана заранее
// (ip_ahead), IP на ней и стоит: шаг не нужен, снимается только
// ip_counted_q, и после пуска та же инструкция читается заново.
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
    // 0 — следующая инструкция; 1 — исполнить текущую: CLRI (0x9) или
    // CLRL (0x8), различаются младшим битом опкода
    input  wire       clr,

    // Состояние проверяемой циклом величины. В Brainfuck ISA это признак
    // нуля текущей ячейки, в Debug ISA — признак нуля счётчика адреса.
    // Выбор делает блок управления, сюда приходит уже готовый признак.
    input  wire       loop_val_zero,

    //------------------------------------------------------------------
    // Выборка
    //------------------------------------------------------------------
    output wire [INSN_WIDTH-1:0] insn,
    output wire                  insn_valid,
    output wire                  insn_eot,     // принят EOT; insn не значим

    //------------------------------------------------------------------
    // Останов и ручное перемещение по программе
    //------------------------------------------------------------------
    input  wire halt_rq,
    input  wire ip_ahead,     // IP уже на следующей, не исполненной инструкции
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
    // Память программ, Valid/Ready
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] mem_addr,
    output wire [INSN_WIDTH-1:0]                     mem_wr_data,
    input  wire [INSN_WIDTH-1:0]                     mem_rd_data,
    output wire                                      mem_valid,
    input  wire                                      mem_ready,
    output wire                                      mem_wr,
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                                      mem_rd_valid,
    input  wire                                      mem_err
/* verilator lint_on UNUSEDSIGNAL */
);

    localparam int unsigned IP_W   = IP_DEKATRON_NUM   * DEKATRON_WIDTH;
    localparam int unsigned LOOP_W = LOOP_DEKATRON_NUM * DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Состояния
    //
    // Каждое состояние, кроме S_IDLE, S_SCAN_EVAL и S_HALT, выдаёт ровно
    // одну операцию одному исполнителю и покидает себя в такте её приёма.
    // Ожидания окончания операции нет: следующее состояние, как и
    // S_IDLE, само ждёт go — готовности всех трёх исполнителей. S_INSN_IN
    // пишет принятый опкод в память в такте рукопожатия.
    //
    // Отдельного ожидания чтения (прежний S_FETCH_W) тоже нет: опкод не
    // защёлкивается, а S_SCAN_EVAL разбирает его, дождавшись go.
    //------------------------------------------------------------------
    localparam logic [3:0]
        S_IDLE      = 4'd0,
        S_IP        = 4'd1,   // шаг счётчика инструкций
        S_FETCH     = 4'd2,   // чтение инструкции
        S_SCAN_EVAL = 4'd4,   // разбор прочитанной скобки
        S_LOOP      = 4'd5,   // шаг счётчика вложенности
        S_INSN_IN   = 4'd6,   // приём опкода при загрузке и его запись
        S_CLR_IP    = 4'd8,   // CLRI
        S_CLR_LOOP  = 4'd9,   // CLRL
        S_HALT      = 4'd10;

    // Двоичное кодирование: Yosys иначе перекодирует автомат в one-hot,
    // а триггер стоит 7 ламп (doc/tube_count_reduction.md §17.2)
    (* fsm_encoding = "binary" *) logic [3:0] state;

    logic                  ip_counted_q;   // IP уже сдвинут под текущую инструкцию
    logic                  scanning_q;     // идёт промотка тела цикла
    logic                  dir_q;          // направление шага IP: 1 — назад
    logic                  key_moved_q;    // ручной шаг уже сделан, ждём отпускания
    logic                  halt_pending_q; // после шага IP уйти в останов
    logic                  overflow_q;
    logic                  eot_q;          // последним принят EOT
    logic                  insn_valid_q;

    //------------------------------------------------------------------
    // Счётчик инструкций
    //------------------------------------------------------------------
    wire            ip_valid;
    wire            ip_ready;
    wire            ip_set_zero;
    wire [IP_W-1:0] ip_out;

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
        .dec       (dir_q),
        .set       (1'b0),
        .set_zero  (ip_set_zero),
        .in        ({IP_W{1'b0}}),
        .out       (ip_out),
        .zero      (),
        .at_top    ()
    );

    assign ip_addr  = ip_out;
    assign mem_addr = ip_out;

    //------------------------------------------------------------------
    // Счётчик глубины вложенности циклов
    //------------------------------------------------------------------
    wire              loop_valid;
    wire              loop_ready;
    wire              loop_dec;
    wire              loop_set_zero;
    wire [LOOP_W-1:0] loop_out;
    wire              loop_is_zero;
    wire              loop_at_top;    // 99: следующий инкремент — переполнение

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
        .zero      (loop_is_zero),
        .at_top    (loop_at_top)
    );

    assign loop_count    = loop_out;
    assign loop_overflow = overflow_q;

    //------------------------------------------------------------------
    // Распознавание скобок
    //
    // Детектор один: он разбирает выходной регистр памяти, а тот в разные
    // моменты держит либо текущую инструкцию (решение о начале промотки),
    // либо только что прочитанную в ходе промотки. Опкоды скобок одинаковы в
    // обоих наборах команд, поэтому режим ISA здесь не нужен.
    //------------------------------------------------------------------
    wire insn_loop_open, insn_loop_close;

    InsnLoopDetector loopDetector (
        .Insn      (mem_rd_data),
        .LoopOpen  (insn_loop_open),
        .LoopClose (insn_loop_close)
    );

    // Условия начала промотки
    wire scan_fwd_req  = insn_loop_open  &  loop_val_zero;   // '[' и ноль
    wire scan_back_req = insn_loop_close & ~loop_val_zero;   // ']' и не ноль
    wire scan_req      = scan_fwd_req | scan_back_req;

    // В промотке своя скобка (по направлению промотки) — инкремент
    // счётчика вложенности, ответная — декремент
    wire loop_inc_next = dir_q ? insn_loop_close : insn_loop_open;

    //------------------------------------------------------------------
    // Выходы и готовность
    //
    // Память отдаёт ready вместе с данными: rd_data достоверен, как только
    // ready вернулся после приёма чтения. Поэтому окончание любой
    // операции определяется одним go, а mem_rd_valid не нужен.
    //------------------------------------------------------------------
    wire go = ip_ready & loop_ready & mem_ready;

    assign insn          = mem_rd_data;
    assign insn_valid    = insn_valid_q;
    assign insn_eot      = eot_q;

    assign ready = (state == S_IDLE) & ~halt_rq & go;

    wire accept = valid & ready;

    // Опкод загрузки пишется в память в такте рукопожатия, поэтому
    // готовность к нему — только при свободной памяти. От insn_in_valid
    // не зависит
    wire in_insn_in = (state == S_INSN_IN);

    assign insn_in_ready = in_insn_in & insn_loading & go;

    wire insn_in_accept = insn_in_valid & insn_in_ready;

    wire end_of_transmission = ({insn_mode, insn_in} == INSN_EOT);

    // Ручной шаг по программе: одна кнопка, один шаг до отпускания
    wire key_step    = (key_prev_ip | key_next_ip) & ~key_moved_q;
    wire key_release = ~key_prev_ip & ~key_next_ip;

    // Парная скобка найдена: счётчик вложенности вернулся в нуль после
    // декремента. В промотке нулём он бывает только в этот момент:
    // стартовая и своя скобки его увеличивают, переполнение ловится до
    // шага. Проверяется в S_IP перед очередным шагом, когда шаг
    // счётчика вложенности уже окончен (go)
    wire scan_done = scanning_q & loop_is_zero;

    //------------------------------------------------------------------
    // Стробы исполнителям — дешифрация состояния (автомат Мура)
    //
    // valid поднимается только при go, то есть при уже поднятом ready
    // исполнителя, и рукопожатие происходит в том же такте. ready
    // исполнителей от valid не зависят, петли нет. Признаки операции
    // (dec, set_zero, wr) значимы только вместе с valid.
    //
    // Направление шага IP держит dir_q (промотка назад, ручной шаг
    // назад), направление счётчика вложенности выводится из опкода:
    // на стартовой скобке ответной скобки нет, значит инкремент.
    //
    // Запись при загрузке — исключение: она следует за insn_in_valid
    // загрузчика (valid за valid, не ready за valid), а опкод берётся
    // прямо с insn_in, пока загрузчик держит его до рукопожатия.
    //------------------------------------------------------------------
    wire in_ip       = (state == S_IP);
    wire in_fetch    = (state == S_FETCH);
    wire in_loop     = (state == S_LOOP);
    wire in_clr_ip   = (state == S_CLR_IP);
    wire in_clr_loop = (state == S_CLR_LOOP);

    assign ip_valid      = ((in_ip & ~scan_done) | in_clr_ip) & go;
    assign ip_set_zero   = in_clr_ip;
    assign loop_valid    = (in_loop | in_clr_loop) & go;
    assign loop_dec      = dir_q ? insn_loop_open : insn_loop_close;
    assign loop_set_zero = in_clr_loop;
    assign mem_valid     = (in_fetch & go) | (insn_in_accept & ~end_of_transmission);
    assign mem_wr        = in_insn_in;
    assign mem_wr_data   = insn_in;

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state          <= S_IDLE;
            ip_counted_q   <= 1'b0;
            scanning_q     <= 1'b0;
            dir_q          <= 1'b0;
            key_moved_q    <= 1'b0;
            halt_pending_q <= 1'b0;
            overflow_q     <= 1'b0;
            eot_q          <= 1'b0;
            insn_valid_q   <= 1'b0;
        end
        // Физический сброс счётчиков обнуляет и состояние выборки:
        // адрес ушёл на начало, прочитанная инструкция недостоверна
        else if (soft_rst | hard_rst) begin
            state          <= S_IDLE;
            ip_counted_q   <= 1'b0;
            scanning_q     <= 1'b0;
            halt_pending_q <= 1'b0;
            insn_valid_q   <= 1'b0;
            eot_q          <= 1'b0;
            overflow_q     <= 1'b0;
        end
        else begin
            case (state)

            //----------------------------------------------------------
            S_IDLE: begin
                if (halt_rq) begin
                    // При останове продвигаем IP на следующую
                    // инструкцию и снимаем признак выборки, чтобы
                    // после возобновления читать заново
                    ip_counted_q <= 1'b0;
                    if (ip_counted_q & ~ip_ahead) begin
                        halt_pending_q <= 1'b1;
                        dir_q          <= 1'b0;
                        state          <= S_IP;
                    end
                    else begin
                        state <= S_HALT;
                    end
                end
                else if (accept) begin
                    eot_q <= 1'b0;

                    if (clr & insn[0]) begin            // CLRI
                        ip_counted_q <= 1'b0;
                        insn_valid_q <= 1'b0;
                        state        <= S_CLR_IP;
                    end
                    else if (clr) begin                 // CLRL
                        overflow_q <= 1'b0;
                        state      <= S_CLR_LOOP;
                    end
                    else begin                          // следующая инструкция
                        if (~ip_counted_q) begin
                            // Первая выборка после сброса: читаем по
                            // текущему адресу, счётчик не двигаем
                            ip_counted_q <= 1'b1;
                            state <= insn_loading ? S_INSN_IN : S_FETCH;
                        end
                        else if (~insn_loading & scan_req & loop_at_top) begin
                            // Счётчик остался на 99 после прежнего
                            // переполнения: инкремент снова переполнит
                            overflow_q <= 1'b1;
                        end
                        else if (~insn_loading & scan_req) begin
                            // Начало промотки: своя скобка учитывается
                            // в счётчике вложенности
                            scanning_q <= 1'b1;
                            dir_q      <= scan_back_req;
                            state      <= S_LOOP;
                        end
                        else begin
                            dir_q <= 1'b0;
                            state <= S_IP;
                        end
                    end
                end
            end

            //----------------------------------------------------------
            // Шаг счётчика инструкций. В промотке сначала проверяем,
            // не найдена ли уже парная скобка: тогда шаг не нужен
            //----------------------------------------------------------
            S_IP: begin
                if (go) begin
                    if (scan_done) begin
                        scanning_q <= 1'b0;   // стоим на парной скобке
                        state      <= S_IDLE;
                    end
                    else if (halt_pending_q) begin
                        halt_pending_q <= 1'b0;
                        insn_valid_q   <= 1'b0;
                        state          <= S_HALT;
                    end
                    else if (insn_loading & ~scanning_q) begin
                        state <= S_INSN_IN;
                    end
                    else begin
                        state <= S_FETCH;
                    end
                end
            end

            //----------------------------------------------------------
            // Чтение инструкции. Окончания чтения ждут S_IDLE (ready) и
            // S_SCAN_EVAL: опкод на выходе памяти достоверен по go
            //----------------------------------------------------------
            S_FETCH: begin
                if (go) begin
                    insn_valid_q <= 1'b1;
                    state        <= scanning_q ? S_SCAN_EVAL : S_IDLE;
                end
            end

            //----------------------------------------------------------
            // Разбор прочитанной инструкции в ходе промотки
            //----------------------------------------------------------
            S_SCAN_EVAL: begin
                if (go) begin
                    if (loop_inc_next & loop_at_top) begin
                        // Переполнение вложенности ловится ДО шага: счётчик
                        // стоит на 99, своя скобка дала бы 99 -> 0
                        // (REQ-CNT-007). Промотку обязательно прервать:
                        // парная скобка уже не найдётся, и машина зависла
                        // бы в бесконечном переборе адресов
                        overflow_q <= 1'b1;
                        scanning_q <= 1'b0;
                        state      <= S_IDLE;
                    end
                    // Своя скобка углубляет вложенность, ответная
                    // поднимает; обычная инструкция — шагаем дальше
                    else if (insn_loop_open | insn_loop_close) state <= S_LOOP;
                    else                                       state <= S_IP;
                end
            end

            //----------------------------------------------------------
            // Шаг счётчика вложенности. Результат (не нуль ли)
            // проверит S_IP, когда шаг окончится
            //----------------------------------------------------------
            S_LOOP: begin
                if (go) state <= S_IP;
            end

            //----------------------------------------------------------
            // Приём опкода при загрузке программы. Опкод уходит в память
            // в такте рукопожатия (EOT не пишется); его окончания ждёт
            // S_IDLE. После сквозной записи insn — принятый опкод
            //----------------------------------------------------------
            S_INSN_IN: begin
                if (~insn_loading) begin
                    state <= S_IDLE;
                end
                else if (insn_in_valid) begin
                    if (go) begin
                        eot_q        <= end_of_transmission;
                        insn_valid_q <= 1'b1;
                        state        <= S_IDLE;
                    end
                end
                else if (key_step) begin
                    // Ручное перемещение по программе во время загрузки
                    key_moved_q <= 1'b1;
                    dir_q       <= key_prev_ip;
                    state       <= S_IP;
                end
                else if (key_release) begin
                    key_moved_q <= 1'b0;
                end
            end

            //----------------------------------------------------------
            // Сброс счётчика по команде
            //----------------------------------------------------------
            S_CLR_IP, S_CLR_LOOP: begin
                if (go) state <= S_IDLE;
            end

            //----------------------------------------------------------
            // Останов с возможностью ручного перемещения
            //----------------------------------------------------------
            S_HALT: begin
                if (~halt_rq) begin
                    state <= S_IDLE;
                end
                else if (key_step) begin
                    key_moved_q <= 1'b1;
                    dir_q       <= key_prev_ip;
                    state       <= S_IP;
                    // После ручного шага инструкция читается заново
                    halt_pending_q <= 1'b1;
                end
                else if (key_release) begin
                    key_moved_q <= 1'b0;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTH
`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && valid && clr && (insn[3:1] != 3'b100))
            $error("IpLine: clr при опкоде %h — не CLRL/CLRI", insn);
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
