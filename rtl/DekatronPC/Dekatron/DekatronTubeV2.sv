//======================================================================
// DekatronTubeV2 — физическая модель коммутаторного декатрона А110
// Кольцевая модель на 30 электродов + временные характеристики
//----------------------------------------------------------------------
// ПРИНЦИП МОДЕЛИ
//
// Состояние прибора — 30-битный регистр cathodes_q в режиме кольца,
// ровно один бит установлен: это и есть текущее положение тлеющего
// разряда. Перемещение разряда — циклический сдвиг вправо/влево.
// Соседние электроды вычислять не нужно: они соседние по построению.
//
//   индекс % 3 == 0 : главный катод, цифра = индекс/3  (0,3,...,27)
//   индекс % 3 == 1 : первый подкатод  (guide A)       (1,4,...,28)
//   индекс % 3 == 2 : второй подкатод  (guide B)       (2,5,...,29)
//
// ФИЗИКА ПЕРЕМЕЩЕНИЯ
//
//   guide_a активен -> разряд притягивается к ближайшему подкатоду A
//   guide_b активен -> разряд притягивается к ближайшему подкатоду B
//   сигналов нет    -> НА ПОДКАТОДЕ РАЗРЯД ОСТАТЬСЯ НЕ МОЖЕТ, он
//                      сваливается на соседний главный катод:
//                        с подкатода A (3k+1) — назад,  на 3k
//                        с подкатода B (3k+2) — вперёд, на 3k+3
//
// Отсюда напрямую следуют все «особые случаи», которые в FSM-модели
// приходилось описывать отдельными таймерами:
//   * A, затем B, затем снятие      -> инкремент (3k -> 3k+3)
//   * B, затем A, затем снятие      -> декремент (3k -> 3k-3)
//   * только A и снятие             -> возврат на исходный катод
//   * только B и снятие             -> возврат на исходный катод
//   * вторая фаза пришла слишком поздно — разряд уже свалился обратно,
//     и новая одиночная фаза снова вернёт его на место
//   * A и B вместе, разряд на подкатоде -> остаётся на нём; со снятием
//     первой линии уходит на вторую. Это перекрытие фаз на стыке A->B:
//     в железе фронты RC-цепей перекрываются, и так и должно быть
//     (Harwell 1951, doc/harwell_1951_review.md §2). Опасен не нахлёст,
//     а зазор: без линий разряд начинает сваливаться назад.
//   * A и B вместе, разряд на главном катоде -> недопустимо: соседние
//     подкатоды A и B равноудалены, направление не определено
// Поэтому параметры PHASE_WINDOW_HS и RETURN_TIMEOUT_HS из TRS v0.1
// БОЛЬШЕ НЕ НУЖНЫ: их роль выполняет FALL_STEP_HS.
//
// ВРЕМЕННЫЕ ХАРАКТЕРИСТИКИ (то, чего не было в исходной модели)
//
// Перемещение разряда не мгновенно. Любой переход между соседними
// электродами занимает время: пока «запрос на перемещение» держится
// стабильно, идёт отсчёт; шаг применяется только по его завершении.
// Импульс короче GUIDE_STEP_HS не сдвигает разряд вообще.
//
// НАЧАЛЬНОЕ ПОЛОЖЕНИЕ
//
// `define DEKATRON_RANDOM_INIT: после включения питания разряд стоит на
// случайном главном катоде из LINES ($urandom), как у настоящего прибора
// (Harwell 1951: «the Dekatron tubes may light in any position»). Привести
// машину в известное состояние может только сброс по катодам
// (doc/harwell_1951_review.md §3). INIT_DIGIT тогда не действует.
//
// ЗАПИСЬ ПО КАТОДАМ [TRS v0.56]
//
// Вход записи — катодные линии line_open_i: 1 — лампа канала записи
// открыта (катод может гореть), 0 — закрыта. Если линия горящего катода
// закрыта не меньше WRITE_MIN_HS, разряд переходит на единственную
// открытую линию; иначе ничего не происходит. Открытых линий нет или
// больше одной при закрытом горящем катоде — недопустимое воздействие
// (invalid_dbg_o), разряд остаётся. Сброс в 0 и в верхнюю позицию — то же
// событие, линии для них закрывает схема снаружи. LINES — катоды с цепью
// возврата (TC-N1: выше MAX_DIGIT её нет, линия всегда 0).
//
// ФИЗИЧЕСКИЙ КОНТРАКТ (TRS v0.1 §2.2)
//
// Модуль НЕ реализует valid/ready/busy. Декатрон только реагирует на
// внешние воздействия заданной длительности, в любом своём внутреннем
// состоянии. Дисциплину операций обеспечивает DekatronCounter.
// main_onehot_o показывает главный катод, на котором стоит разряд, при
// любых воздействиях (линии чтения отдельные, TRS v0.24), и ноль, пока
// разряд на подкатоде.
//======================================================================

`default_nettype none

module DekatronTubeV2 #(
    // Время перехода между соседними электродами при активном подкатоде.
    // Играет роль GUIDE_MIN_HS из TRS v0.1: импульс короче не даёт шага.
    parameter unsigned GUIDE_STEP_HS    = 1,

    // Время сваливания с подкатода на соседний главный катод
    // при снятии подкатодных сигналов.
    parameter unsigned FALL_STEP_HS     = 1,

    // Предельная длительность подкатодного импульса (только для assertion)
    parameter unsigned GUIDE_MAX_HS     = 20,

    // Запись по катоду (и сброс — то же событие), такты hsClk (1 мкс при
    // Clk 100 кГц). Оценка до измерений (OPEN-013): запись по handshake
    // держится один такт Clk [TRS v0.24]
    parameter unsigned WRITE_MIN_HS     = 5,

    // Катоды с цепью возврата (TC-N1)
    parameter logic [9:0]  LINES            = 10'h3FF,

    // Начальное положение разряда после включения питания
    parameter logic [3:0]  INIT_DIGIT       = 4'd0,

    // Какая пара фаз даёт инкремент: 1 = A,затем B
    parameter bit          INC_BY_A_THEN_B  = 1'b1,

    // Прямая установка кольца — НЕ физический сигнал, только для
    // инициализации симуляции/эмулятора и отладки
    parameter bit          EN_SIM_PRESET    = 1'b1,

    parameter bit          EN_DEBUG_OUTPUTS = 1'b1
)(
    input  wire         hsClk,

    // Подкатодные линии
    input  wire         guide_a_i,
    input  wire         guide_b_i,

    // Катодные линии: 1 — открыта (катод может гореть), 0 — закрыта
    input  wire [9:0]   line_open_i,

    // Прямая установка кольца (не физическая, см. EN_SIM_PRESET)
    input  wire         sim_preset_en_i,
    input  wire [29:0]  sim_preset_cathodes_i,

    // Наблюдаемый выход по главным катодам
    output logic [9:0]  main_onehot_o,

    // Debug-выходы
    output logic [29:0] cathodes_dbg_o,
    output logic        on_guide_dbg_o,
    output logic        moving_dbg_o,
    output logic        in_write_reset_dbg_o,
    output logic        settled_dbg_o,
    output logic        invalid_dbg_o
);

    localparam int unsigned CNT_W = 16;

    // Маски классов электродов
    localparam logic [29:0] MASK_MAIN = 30'b001001001001001001001001001001;
    localparam logic [29:0] MASK_GA   = 30'b010010010010010010010010010010;
    localparam logic [29:0] MASK_GB   = 30'b100100100100100100100100100100;

    //------------------------------------------------------------------
    // Состояние
    //------------------------------------------------------------------
    logic [29:0]      cathodes_q;
    logic [CNT_W-1:0] move_timer_q;
    logic [1:0]       move_dir_q;     // последнее направление перемещения
    logic [CNT_W-1:0] wr_timer_q;
    logic             wr_settled_q;
    logic [9:0]       wr_lines_q;       // линии текущей операции
    logic             wr_active_q;      // операция шла на прошлом такте
    //verilator lint_off UNUSEDSIGNAL
    logic             illegal_q;
    //verilator lint_on UNUSEDSIGNAL

    localparam logic [1:0] MOVE_NONE = 2'd0;
    localparam logic [1:0] MOVE_FWD  = 2'd1;   // индекс +1
    localparam logic [1:0] MOVE_BACK = 2'd2;   // индекс -1

`ifndef SYNTH
    //------------------------------------------------------------------
    // Кольцевые сдвиги
    //------------------------------------------------------------------
    function automatic logic [29:0] rot_fwd(input logic [29:0] c);
        rot_fwd = {c[28:0], c[29]};      // idx -> idx+1
    endfunction

    function automatic logic [29:0] rot_back(input logic [29:0] c);
        rot_back = {c[0], c[29:1]};      // idx -> idx-1
    endfunction

    function automatic bit is_onehot10(input logic [9:0] v);
        is_onehot10 = (v != 10'd0) && ((v & (v - 10'd1)) == 10'd0);
    endfunction

    function automatic bit is_onehot30(input logic [29:0] v);
        is_onehot30 = (v != 30'd0) && ((v & (v - 30'd1)) == 30'd0);
    endfunction

    // Развернуть позицию главного катода в 30-битное кольцо
    function automatic logic [29:0] main_to_ring(input logic [9:0] pos10);
        main_to_ring = 30'd0;
        for (int i = 0; i < 10; i++)
            if (pos10[i]) main_to_ring[3*i] = 1'b1;
    endfunction

    //------------------------------------------------------------------
    // Классификация текущего положения разряда
    //------------------------------------------------------------------
    wire on_main = |(cathodes_q & MASK_MAIN);
    wire on_ga   = |(cathodes_q & MASK_GA);
    wire on_gb   = |(cathodes_q & MASK_GB);

    //------------------------------------------------------------------
    // Внешние воздействия
    //------------------------------------------------------------------
    // Направление задаётся параметром: меняем роли линий, а не логику
    wire ga = INC_BY_A_THEN_B ? guide_a_i : guide_b_i;
    wire gb = INC_BY_A_THEN_B ? guide_b_i : guide_a_i;

    logic [9:0] main_now;
    always_comb
        for (int i = 0; i < 10; i++) main_now[i] = cathodes_q[3*i];

    // Закрыта хоть одна линия: идёт запись, подкатоды должны молчать
    wire wr_any_active = |(~line_open_i & LINES);
    // Линия горящего катода закрыта: разряд обязан перейти. С подкатода
    // разряд уходит на цель записи
    wire wr_needed     = on_main ? |(main_now & ~line_open_i) : wr_any_active;

    wire guides_both = guide_a_i && guide_b_i;
    // Перекрытие фаз допустимо, пока разряд на подкатоде (см. шапку)
    wire guides_both_bad = guides_both && on_main;

    // Цель записи — единственная открытая линия
    wire [29:0] wr_target_ring  = main_to_ring(line_open_i);
    wire        wr_target_valid = is_onehot10(line_open_i & LINES);

    //------------------------------------------------------------------
    // Минимальная длительность воздействия. С TRS v0.24 линия записи —
    // это сам такт accept, и модель считает чистую физическую
    // длительность.
    //------------------------------------------------------------------
    wire [CNT_W-1:0] wr_min_hs = CNT_W'(WRITE_MIN_HS);

    //------------------------------------------------------------------
    // Требуемое перемещение разряда
    //
    // Во время записи/сброса главные катоды заблокированы, разряд
    // удерживается принудительно — перемещение по подкатодам не идёт.
    //------------------------------------------------------------------
    logic [1:0]       move_dir;
    logic [CNT_W-1:0] move_time;

    always_comb begin
        move_dir  = MOVE_NONE;
        move_time = CNT_W'(GUIDE_STEP_HS);

        if (wr_any_active || guides_both) begin
            // Запись/сброс или обе линии: разряд не движется. На
            // подкатоде это перекрытие фаз, на главном катоде — ошибка
            move_dir = MOVE_NONE;
        end
        else if (ga && !gb) begin
            // Притяжение к ближайшему подкатоду A (3k+1)
            move_time = CNT_W'(GUIDE_STEP_HS);
            if      (on_main) move_dir = MOVE_FWD;    // 3k   -> 3k+1
            else if (on_gb)   move_dir = MOVE_BACK;   // 3k+2 -> 3k+1
            else              move_dir = MOVE_NONE;   // уже на 3k+1
        end
        else if (gb && !ga) begin
            // Притяжение к ближайшему подкатоду B (3k+2)
            move_time = CNT_W'(GUIDE_STEP_HS);
            if      (on_main) move_dir = MOVE_BACK;   // 3k   -> 3k-1
            else if (on_ga)   move_dir = MOVE_FWD;    // 3k+1 -> 3k+2
            else              move_dir = MOVE_NONE;   // уже на 3k+2
        end
        else begin
            // Сигналов нет: на подкатоде разряд остаться не может
            move_time = CNT_W'(FALL_STEP_HS);
            if      (on_ga) move_dir = MOVE_BACK;     // 3k+1 -> 3k
            else if (on_gb) move_dir = MOVE_FWD;      // 3k+2 -> 3k+3
            else            move_dir = MOVE_NONE;     // на главном катоде
        end
    end

    // Перезапуск отсчёта при смене направления перемещения
    wire move_restart = (move_dir != move_dir_q);
    wire [CNT_W-1:0] move_next = move_restart ? CNT_W'(1)
                                              : (move_timer_q + CNT_W'(1));
    wire move_done = (move_dir != MOVE_NONE) && (move_next >= move_time);

    //------------------------------------------------------------------
    // Контроль длительности подкатодных импульсов (только диагностика)
    //------------------------------------------------------------------
    logic [CNT_W-1:0] ga_high_q, gb_high_q;

    wire ga_too_long = guide_a_i && ((ga_high_q + CNT_W'(1)) > CNT_W'(GUIDE_MAX_HS));
    wire gb_too_long = guide_b_i && ((gb_high_q + CNT_W'(1)) > CNT_W'(GUIDE_MAX_HS));

    //------------------------------------------------------------------
    // Начальное состояние (не физический сброс, а состояние после
    // включения питания и зажигания разряда)
    //------------------------------------------------------------------
    initial begin
        cathodes_q       = 30'd1 << (3*INIT_DIGIT);
`ifdef DEKATRON_RANDOM_INIT
        begin
            int unsigned d;
            d = $urandom % 10;
            while (!LINES[d]) d = $urandom % 10;
            cathodes_q = 30'd1 << (3*d);
        end
`endif
        move_timer_q     = '0;
        move_dir_q       = MOVE_NONE;
        wr_timer_q       = '0;
        wr_settled_q     = 1'b0;
        wr_lines_q       = '1;
        wr_active_q      = 1'b0;
        illegal_q        = 1'b0;
        ga_high_q        = '0;
        gb_high_q        = '0;
    end

    //------------------------------------------------------------------
    // Основной процесс
    //------------------------------------------------------------------
    always_ff @(posedge hsClk) begin

        // --- счётчики длительности подкатодных импульсов (с насыщением)
        if (guide_a_i) begin
            if (!(&ga_high_q)) ga_high_q <= ga_high_q + CNT_W'(1);
        end else ga_high_q <= '0;

        if (guide_b_i) begin
            if (!(&gb_high_q)) gb_high_q <= gb_high_q + CNT_W'(1);
        end else gb_high_q <= '0;

        // --- диагностика недопустимых воздействий
        illegal_q <= guides_both_bad ||
                     ga_too_long || gb_too_long ||
                     (wr_any_active && (guide_a_i || guide_b_i)) ||
                     !is_onehot30(cathodes_q);

        //--------------------------------------------------------------
        // Запись: линия горящего катода закрыта не менее MIN тактов —
        // разряд переходит на единственную открытую линию. Подкатоды
        // на это время заблокированы.
        //--------------------------------------------------------------
        if (wr_any_active) begin
            move_timer_q <= '0;
            move_dir_q   <= MOVE_NONE;
            wr_active_q  <= 1'b1;

            if (!wr_active_q || (line_open_i != wr_lines_q)) begin
                // Начало новой операции. Смена линий без снятия
                // воздействия — тоже новая операция: отсчёт заново.
                wr_lines_q   <= line_open_i;
                wr_timer_q   <= CNT_W'(1);
                wr_settled_q <= 1'b0;
            end
            else if (!wr_settled_q) begin
                wr_timer_q <= wr_timer_q + CNT_W'(1);

                // Операция засчитывается ровно на MIN-м такте удержания;
                // повторного срабатывания каждый такт не происходит.
                if ((wr_timer_q + CNT_W'(1)) >= wr_min_hs) begin
                    // Горящий катод закрыт, а открыта не одна линия:
                    // разряд зажёгся бы где придётся
                    if (wr_needed && wr_target_valid)
                        cathodes_q <= wr_target_ring;
                    else if (wr_needed)
                        illegal_q  <= 1'b1;
                    wr_settled_q <= 1'b1;
                end
            end
        end
        else begin
            // Воздействие снято
            wr_timer_q   <= '0;
            wr_settled_q <= 1'b0;
            wr_active_q  <= 1'b0;
            wr_lines_q   <= '1;

            //----------------------------------------------------------
            // Перемещение разряда по кольцу
            //----------------------------------------------------------
            move_dir_q <= move_dir;

            if (move_dir == MOVE_NONE) begin
                move_timer_q <= '0;
            end
            else if (move_done) begin
                cathodes_q   <= (move_dir == MOVE_FWD) ? rot_fwd(cathodes_q)
                                                       : rot_back(cathodes_q);
                move_timer_q <= '0;
            end
            else begin
                move_timer_q <= move_next;
            end
        end

        //--------------------------------------------------------------
        // Прямая установка кольца — наивысший приоритет.
        // Не физический сигнал: только инициализация симуляции.
        //--------------------------------------------------------------
        if (EN_SIM_PRESET && sim_preset_en_i) begin
            cathodes_q   <= sim_preset_cathodes_i;
            move_timer_q <= '0;
            move_dir_q   <= MOVE_NONE;
            wr_timer_q   <= '0;
            wr_settled_q <= 1'b0;
            wr_active_q  <= 1'b0;
            wr_lines_q   <= '1;
        end
    end

    //------------------------------------------------------------------
    // Выходы
    //------------------------------------------------------------------
    logic [9:0] main_decoded;
    always_comb begin
        for (int i = 0; i < 10; i++)
            main_decoded[i] = cathodes_q[3*i];
    end

    // Линии чтения главных катодов отдельные и читаются всегда, в том
    // числе под записью и при поднятом подкатоде [TRS v0.24]: показывают
    // катод, на котором стоит разряд, и ноль, пока он на подкатоде.
    // Достоверно показание только на фронте Clk после операции — это
    // дисциплина счётчика, а не модели.
    assign main_onehot_o = on_main ? main_decoded : 10'b0;

    generate
        if (EN_DEBUG_OUTPUTS) begin : g_dbg_on
            assign cathodes_dbg_o       = cathodes_q;
            assign on_guide_dbg_o       = on_ga || on_gb;
            assign moving_dbg_o         = (move_dir != MOVE_NONE);
            assign in_write_reset_dbg_o = wr_any_active;
            assign settled_dbg_o        = wr_any_active && wr_settled_q;
            assign invalid_dbg_o        = illegal_q || guides_both_bad;
        end
        else begin : g_dbg_off
            assign cathodes_dbg_o       = 30'b0;
            assign on_guide_dbg_o       = 1'b0;
            assign moving_dbg_o         = 1'b0;
            assign in_write_reset_dbg_o = 1'b0;
            assign settled_dbg_o        = 1'b0;
            assign invalid_dbg_o        = 1'b0;
        end
    endgenerate
`endif
    //------------------------------------------------------------------
    // Assertions (TRS v0.1 §13)
    //------------------------------------------------------------------
`ifdef ASSERTIONS
    DekatronTubeV2_assertions #(
        .LINES (LINES)
    ) u_assertions (
        .hsClk       (hsClk),
        .guide_a_i   (guide_a_i),
        .guide_b_i   (guide_b_i),
        .line_open_i (line_open_i),
        .cathodes_q  (cathodes_q)
    );
`endif


endmodule

`default_nettype wire
