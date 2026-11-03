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
// Шаг IP и останов к памяти не обращаются, а следующее обращение
// бывает лишь после того, как блок управления закончил с текущей
// инструкцией. Поэтому insn — это прямо mem_rd_data.
//
// Единственный опкод, которого в памяти нет, — EOT (код LD, 0xB, в
// потоке загрузки). О нём сообщает отдельный триггер insn_eot.
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

`default_nettype none

`ifndef SYNTH
// Модель вентиля сброса автомата (ячейка vtube_cells.lib). В синтезе стоит
// сама ячейка: ABC не растворяет её в логике переходов (TC-N2)
module NOR2_N16 (input wire A, input wire B, output wire Y);
    assign Y = ~(A | B);
endmodule

// Модель антидребезга кнопки пульта (sch/logic/KEYDB_N16, TC-N3). В синтезе
// ячейка берётся из vtube_cells.lib: функции у неё нет, ABC её не использует.
// Дребезг контактов в модели не виден: на входе уже уровень «нажата».
module KEYDB_N16 (
    input  wire A,
    input  wire B,
    output wire Y
);
    assign Y = A | B;
endmodule
`endif

module IpLine #(
    // Сколько старших декад аппаратный сброс ставит в девятку.
    // Для пяти декатронов это даёт 99990 — начало загрузчика.
    parameter unsigned HARD_RST_D_CNT    = IP_DEKATRON_NUM - 1,

    // Чтение счётчика циклов нужно только для индикации в эмуляторе
    parameter bit          LOOP_READ         = 1'b0
)(
    input  wire rst_n,        // только модельный сброс RC-элементов задержки счётчиков; триггеры клея сбрасывают линии (TC-O5)
    input  wire clk,
`ifndef DEKATRON_DELAY_MODEL
    input  wire hs_clk,       // только тактовая модель декатронов
`endif

    // Физические линии сброса счётчиков (удерживает реле времени)
    input  wire soft_rst,
    input  wire hard_rst,

    //------------------------------------------------------------------
    // Командный интерфейс
    //------------------------------------------------------------------
    input  wire       valid,      // следующая инструкция
    output wire       ready,

    // Состояние проверяемой циклом величины: для [ ] — признак нуля
    // текущей ячейки, для { } — признак нуля счётчика адреса.
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
    input  wire [INSN_WIDTH-1:0] insn_in,
    input  wire                  insn_in_valid,
    output wire                  insn_in_ready,

    //------------------------------------------------------------------
    // Состояние для блока управления и индикации
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ip_addr,      // тетрады активным нулём (TC-O3)
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] loop_count,   // тетрады активным нулём (TC-O3)
    output wire                                        loop_overflow,

    //------------------------------------------------------------------
    // Память программ, Valid/Ready
    //------------------------------------------------------------------
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] mem_addr,   // активным нулём, память инвертирует сама
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
    // Коды — те, что выбирал Yosys при fsm_encoding = "binary" (doc/isa16.md
    // §6.1). Как FSM автомат больше не извлекается: на входе D триггеров
    // стоит вентиль сброса (state_d), и коды остаются как написаны
    localparam logic [2:0]
        S_IDLE      = 3'd0,
        S_IP        = 3'd5,   // шаг счётчика инструкций
        S_FETCH     = 3'd2,   // чтение инструкции
        S_SCAN_EVAL = 3'd1,   // разбор прочитанной скобки
        S_LOOP      = 3'd6,   // шаг счётчика вложенности
        S_INSN_IN   = 3'd4,   // приём опкода при загрузке и его запись
        S_HALT      = 3'd3;

    // Двоичное кодирование: Yosys иначе перекодирует автомат в one-hot,
    // а триггер стоит 7 ламп (doc/tube_count_reduction.md §17.2)
    logic [2:0] state;
    logic [2:0] state_nx;   // следующее состояние без сброса
    logic [2:0] state_d;    // вход D: сброс линиями поверх state_nx

    logic                  ip_counted_q;   // IP уже сдвинут под текущую инструкцию
    logic                  scanning_q;     // идёт промотка тела цикла
    logic                  dir_q;          // направление шага IP: 1 — назад
    logic                  key_next_s;     // кнопка «вперёд», синхронизирована с Clk (TC-N3)
    logic                  key_moved_q;    // нажатие тактом раньше: шаг на фронте нажатия
    logic                  halt_pending_q; // после шага IP уйти в останов
    logic                  overflow_q;
    logic                  eot_q;          // последним принят EOT
    logic                  insn_valid_q;

    //------------------------------------------------------------------
    // Счётчик инструкций
    //------------------------------------------------------------------
    wire            ip_valid;
    wire            key_mode;      // IpLine стоит, счётчик IP отдан кнопкам (TC-N3)
    wire            key_dir_mode;  // S_HALT / S_INSN_IN: dir_q держит кнопку «назад»
    wire            ip_ready;
    wire [IP_W-1:0] ip_out_n;     // тетрады активным нулём (TC-O3)

    DekatronCounter #(
        .D_NUM          (IP_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b0),
        .TOP_LIMIT_MODE (1'b0),
        .HARD_RST_D_CNT (HARD_RST_D_CNT)
    ) ip_counter (
        .rst_n     (rst_n),
        .clk       (clk),
`ifndef DEKATRON_DELAY_MODEL
        .hs_clk    (hs_clk),
`endif
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (ip_valid),
        .ready     (ip_ready),
        .dec       (dir_q),
        .set       (1'b0),
        .set_zero  (1'b0),
        .in_n      ({IP_W{1'b1}}),
        .out_n     (ip_out_n),
        .zero      (),
        .at_top    ()
    );

    assign ip_addr  = ip_out_n;
    assign mem_addr = ip_out_n;

    //------------------------------------------------------------------
    // Счётчик глубины вложенности циклов
    //------------------------------------------------------------------
    wire              loop_valid;
    wire              loop_ready;
    wire              loop_dec;
    wire [LOOP_W-1:0] loop_out_n;  // тетрады активным нулём (TC-O3)
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
`ifndef DEKATRON_DELAY_MODEL
        .hs_clk    (hs_clk),
`endif
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (loop_valid),
        .ready     (loop_ready),
        .dec       (loop_dec),
        .set       (1'b0),
        .set_zero  (1'b0),
        .in_n      ({LOOP_W{1'b1}}),
        .out_n     (loop_out_n),
        .zero      (loop_is_zero),
        .at_top    (loop_at_top)
    );

    assign loop_count    = loop_out_n;
    assign loop_overflow = overflow_q;

    //------------------------------------------------------------------
    // Распознавание скобок
    //
    // Детектор один: он разбирает выходной регистр памяти, а тот в разные
    // моменты держит либо текущую инструкцию (решение о начале промотки),
    // либо только что прочитанную в ходе промотки. Скобки [ ] и { } —
    // x11x, и промотка считает их вместе: вкладывать один вид в другой
    // нельзя ({ } нужны только загрузчику).
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

    // После переполнения вложенности IpLine больше не отвечает до сброса
    // линиями: машина стоит (TC-N2, REQ-CNT-007), MachineCtrl ждёт выборку
    assign ready = (state == S_IDLE) & ~halt_rq & go & ~overflow_q;

    wire accept = valid & ready;

    // Опкод загрузки пишется в память в такте рукопожатия, поэтому
    // готовность к нему — только при свободной памяти. От insn_in_valid
    // не зависит
    wire in_insn_in = (state == S_INSN_IN);

    assign insn_in_ready = in_insn_in & insn_loading & go;

    wire insn_in_accept = insn_in_valid & insn_in_ready;

    wire end_of_transmission = (insn_in == 4'hB);   // LD

    // Ручной шаг по программе (TC-N3): одно нажатие — один шаг счётчика IP
    // прямо из останова или из ожидания опкода при загрузке, без переходов
    // автомата. Кнопки переключающие, антидребезг KEYDB_N16 (триггер на
    // контактах) на каждую. Синхронизаторы: для «вперёд» — key_next_s, для
    // «назад» — сам dir_q, который в S_HALT и S_INSN_IN каждый такт берёт
    // уровень кнопки (при входе в эти состояния он обнулён). Шаг и его
    // направление при «назад» идут с одного триггера, поэтому асинхронная
    // кнопка не может дать шаг не в ту сторону, а dec счётчика остаётся
    // выходом триггера: любой мультиплексор в dec удлиняет путь до защёлок
    // переноса сверх окна команды (synth_sim.sh -t). key_moved_q выделяет
    // фронт нажатия: ip_valid меняется только на фронте Clk.
    wire key_prev_db, key_next_db;
    KEYDB_N16 keyDbPrev (.A (key_prev_ip), .B (1'b0), .Y (key_prev_db));
    KEYDB_N16 keyDbNext (.A (key_next_ip), .B (1'b0), .Y (key_next_db));

    wire key_prev_s = dir_q & key_dir_mode;   // «назад», синхронизирована

    always_ff @(posedge clk) begin
        key_next_s  <= key_next_db;
        key_moved_q <= key_prev_s | key_next_s;
    end

    wire key_step = (key_prev_s | key_next_s) & ~key_moved_q;

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

    assign key_dir_mode = (state == S_HALT) | in_insn_in;
    assign key_mode = ((state == S_HALT) & halt_rq) |
                      (in_insn_in & insn_loading & ~insn_in_valid);
    assign ip_valid = ((in_ip & ~scan_done) | (key_mode & key_step)) & go;
    assign loop_valid    = in_loop & go;
    assign loop_dec      = dir_q ? insn_loop_open : insn_loop_close;
    assign mem_valid     = (in_fetch & go) | (insn_in_accept & ~end_of_transmission);
    assign mem_wr        = in_insn_in;
    assign mem_wr_data   = insn_in;

    //------------------------------------------------------------------
    // Основной автомат
    //
    // Переходы — в always_comb (state_nx), сброс линиями — отдельный вентиль
    // NOR2_N16 на входе D каждого бита: state_d = ~(rst | ~state_nx). Если
    // сброс — ветка автомата, ABC вплетает его в логику переходов вместе с
    // самим state, и нетлист с нулевыми задержками не снимает X включения:
    // при поднятой линии сброса state оставался X, хотя из любого кода
    // логика даёт S_IDLE (TC-N2, doc/tube_count_below_1000.md §13). В лампах
    // X нет, но нетлист X не маскирует, а удача ABC — не гарантия. Цена —
    // 3 × ½ 6Н16Б и потеря оптимизаций FSM Yosys, всего ≈ +7 ламп.
    // Пустые ветки в флаговом always_ff ниже оставлены нарочно: без них
    // Yosys строит другие мультиплексоры и IpLine дороже на ≈ 7 ламп
    // (8 seed), хотя логика та же
    //------------------------------------------------------------------
    // Все триггеры сбрасывают линии soft_rst/hard_rst синхронно или они
    // пишутся до чтения; rst_n в ламповой машине нет: его роль играет
    // аппаратный сброс реле времени при включении (REQ-REF-011, TC-O5)

    always_comb begin
        state_nx = state;   // остаёмся, пока исполнитель не готов (go)
        case (state)
        S_IDLE:
            if (halt_rq) state_nx = (ip_counted_q & ~ip_ahead) ? S_IP : S_HALT;
            else if (accept) begin
                if (~ip_counted_q)                              state_nx = insn_loading ? S_INSN_IN : S_FETCH;
                else if (~insn_loading & scan_req & loop_at_top) state_nx = S_IDLE;
                else if (~insn_loading & scan_req)               state_nx = S_LOOP;
                else                                             state_nx = S_IP;
            end
        S_IP:
            if (go) begin
                if (scan_done)                          state_nx = S_IDLE;
                else if (halt_pending_q)                state_nx = S_HALT;
                else if (insn_loading & ~scanning_q)    state_nx = S_INSN_IN;
                else                                    state_nx = S_FETCH;
            end
        S_FETCH:     if (go) state_nx = scanning_q ? S_SCAN_EVAL : S_IDLE;
        S_SCAN_EVAL:
            if (go) begin
                if (loop_inc_next & loop_at_top)          state_nx = S_IDLE;
                else if (insn_loop_open | insn_loop_close) state_nx = S_LOOP;
                else                                       state_nx = S_IP;
            end
        S_LOOP:      if (go) state_nx = S_IP;
        S_INSN_IN:
            if (~insn_loading)                state_nx = S_IDLE;
            else if (insn_in_valid & go)      state_nx = S_IDLE;
        S_HALT:      if (~halt_rq) state_nx = S_IDLE;
        default:     state_nx = S_IDLE;
        endcase
    end

    wire rst_line = soft_rst | hard_rst;
    NOR2_N16 stateRst [2:0] (.A ({3{rst_line}}), .B (~state_nx), .Y (state_d));

    always_ff @(posedge clk) state <= state_d;

    always_ff @(posedge clk) begin
        // Физический сброс счётчиков обнуляет и состояние выборки:
        // адрес ушёл на начало, прочитанная инструкция недостоверна
        if (soft_rst | hard_rst) begin
            ip_counted_q   <= 1'b0;
            scanning_q     <= 1'b0;
            halt_pending_q <= 1'b0;
            insn_valid_q   <= 1'b0;
            eot_q          <= 1'b0;
            overflow_q     <= 1'b0;
            dir_q          <= 1'b0;   // входит в key_prev_s (TC-N3): без X после сброса
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
                    end
                    else begin
                        dir_q <= 1'b0;   // в S_HALT dir_q — синхронизатор «назад»
                    end
                end
                else if (accept) begin
                    eot_q <= 1'b0;

                    if (~ip_counted_q) begin
                        // Первая выборка после сброса: читаем по
                        // текущему адресу, счётчик не двигаем
                        ip_counted_q <= 1'b1;
                        dir_q        <= 1'b0;   // в S_INSN_IN — синхронизатор «назад»
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
                    end
                    else begin
                        dir_q <= 1'b0;
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
                    end
                    else if (halt_pending_q) begin
                        halt_pending_q <= 1'b0;
                        insn_valid_q   <= 1'b0;
                    end
                    else if (insn_loading & ~scanning_q) begin
                        // в S_INSN_IN (state_nx)
                    end
                    else begin
                        // в S_FETCH (state_nx)
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
                    end
                    // Своя скобка углубляет вложенность, ответная
                    // поднимает; обычная инструкция — шагаем дальше (state_nx)
                    else if (insn_loop_open | insn_loop_close) begin end
                    else                                       begin end
                end
            end

            //----------------------------------------------------------
            // Шаг счётчика вложенности. Результат (не нуль ли)
            // проверит S_IP, когда шаг окончится
            //----------------------------------------------------------
            S_LOOP: begin
                if (go) begin end   // в S_IP (state_nx)
            end

            //----------------------------------------------------------
            // Приём опкода при загрузке программы. Опкод уходит в память
            // в такте рукопожатия (EOT не пишется); его окончания ждёт
            // S_IDLE. После сквозной записи insn — принятый опкод
            //----------------------------------------------------------
            S_INSN_IN: begin
                if (~insn_loading) begin
                    // загрузка снята: в S_IDLE (state_nx)
                end
                else if (insn_in_valid) begin
                    if (go) begin
                        eot_q        <= end_of_transmission;
                        insn_valid_q <= 1'b1;
                    end
                end
                // Иначе — ручное перемещение по программе во время
                // загрузки: шаг счётчика IP прямо отсюда (key_mode, TC-N3)
                else begin
                    dir_q <= key_prev_db;
                end
            end

            //----------------------------------------------------------
            // Останов с возможностью ручного перемещения
            //----------------------------------------------------------
            S_HALT: begin
                if (~halt_rq) begin
                    // пуск: в S_IDLE (state_nx)
                end
                else begin
                    dir_q <= key_prev_db;
                    // Ручной шаг идёт прямо отсюда (key_mode, TC-N3);
                    // после него инструкция читается заново
                    if (key_step & go) insn_valid_q <= 1'b0;
                end
            end

            default: ;
            endcase
        end
    end

`ifndef SYNTH
`ifdef ASSERTIONS
    always @(posedge clk) begin
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
