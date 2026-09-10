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
// ФИЗИЧЕСКИЙ КОНТРАКТ (TRS v0.1 §2.2)
//
// Модуль НЕ реализует valid/ready/busy. Декатрон только реагирует на
// внешние воздействия заданной длительности, в любом своём внутреннем
// состоянии. Дисциплину операций обеспечивает DekatronCounterV2.
// main_onehot_o валиден только когда разряд стоит на главном катоде
// и внешних воздействий нет.
//======================================================================

`default_nettype none

module DekatronTubeV2 #(
    // Отношение временных баз (справочное)
    //parameter unsigned HS_PER_CLK       = 10,

    // Время перехода между соседними электродами при активном подкатоде.
    // Играет роль GUIDE_MIN_HS из TRS v0.1: импульс короче не даёт шага.
    parameter unsigned GUIDE_STEP_HS    = 2,

    // Время сваливания с подкатода на соседний главный катод
    // при снятии подкатодных сигналов.
    parameter unsigned FALL_STEP_HS     = 3,

    // Предельная длительность подкатодного импульса (только для assertion)
    parameter unsigned GUIDE_MAX_HS     = 20,

    // Запись числа по катоду
    parameter unsigned WRITE_MIN_HS     = 100,
    //parameter unsigned WRITE_MAX_HS     = 200,

    // Сброс импульсом по катоду
    parameter unsigned RESET_MIN_HS     = 100,
    //parameter unsigned RESET_MAX_HS     = 200,

    // Сброс в произвольный «верхний» катод.
    // RESET_N_POS = 9 соответствует reset9 из TRS v0.1;
    // RESET_N_POS = 5 — линия сброса в 5 для счётчика данных до 255.
    parameter bit          EN_RESETN        = 1'b0,
    parameter unsigned RESET_N_POS      = 9,

    // Начальное положение разряда после включения питания
    parameter logic [3:0]  INIT_DIGIT       = 4'd0,

    // Какая пара фаз даёт инкремент: 1 = A,затем B
    parameter bit          INC_BY_A_THEN_B  = 1'b1,

    // Прямая установка кольца — НЕ физический сигнал, только для
    // инициализации симуляции/эмулятора и отладки
    parameter bit          EN_SIM_PRESET    = 1'b1,

    parameter bit          EN_ASSERTIONS    = 1'b1,
    parameter bit          EN_DEBUG_OUTPUTS = 1'b1
)(
    input  wire         hsClk,

    // Подкатодные линии
    input  wire         guide_a_i,
    input  wire         guide_b_i,

    // Запись числа по катоду
    input  wire         write_en_i,
    input  wire [9:0]   write_pos_i,      // one-hot

    // Сбросы импульсом по катоду
    input  wire         reset0_i,         // в катод 0
    input  wire         resetN_i,         // в катод RESET_N_POS

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
    logic [9:0]       wr_pos_latched_q;
    logic [29:0]      wr_target_q;      // цель текущей операции
    logic             wr_active_q;      // операция шла на прошлом такте
    //verilator lint_off UNUSEDSIGNAL
    logic             illegal_q;
    //verilator lint_on UNUSEDSIGNAL

    localparam logic [1:0] MOVE_NONE = 2'd0;
    localparam logic [1:0] MOVE_FWD  = 2'd1;   // индекс +1
    localparam logic [1:0] MOVE_BACK = 2'd2;   // индекс -1

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

    wire resetN_enabled = EN_RESETN && resetN_i;

    wire wr_any_active = write_en_i || reset0_i || resetN_enabled;

    wire wr_conflict = (write_en_i && reset0_i)      ||
                       (write_en_i && resetN_enabled) ||
                       (reset0_i   && resetN_enabled);

    wire resetN_illegal_disabled = (!EN_RESETN) && resetN_i;

    wire guides_both = guide_a_i && guide_b_i;

    // Цель операции записи/сброса
    logic [29:0] wr_target_ring;
    logic        wr_target_valid;
    always_comb begin
        wr_target_ring  = 30'd0;
        wr_target_valid = 1'b0;
        if (write_en_i && !reset0_i && !resetN_enabled) begin
            wr_target_ring  = main_to_ring(write_pos_i);
            wr_target_valid = is_onehot10(write_pos_i);
        end
        else if (reset0_i && !write_en_i && !resetN_enabled) begin
            wr_target_ring  = 30'd1;                       // катод 0
            wr_target_valid = 1'b1;
        end
        else if (resetN_enabled && !write_en_i && !reset0_i) begin
            wr_target_ring  = 30'd1 << (3*RESET_N_POS);    // катод RESET_N_POS
            wr_target_valid = 1'b1;
        end
    end

    wire [CNT_W-1:0] wr_min_hs = write_en_i ? CNT_W'(WRITE_MIN_HS)
                                            : CNT_W'(RESET_MIN_HS);

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
            // Запись/сброс или недопустимая комбинация: разряд не движется
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

    wire write_pos_changed = write_en_i && wr_settled_q &&
                             (write_pos_i != wr_pos_latched_q);

    //------------------------------------------------------------------
    // Начальное состояние (не физический сброс, а состояние после
    // включения питания и зажигания разряда)
    //------------------------------------------------------------------
    initial begin
        cathodes_q       = 30'd1 << (3*INIT_DIGIT);
        move_timer_q     = '0;
        move_dir_q       = MOVE_NONE;
        wr_timer_q       = '0;
        wr_settled_q     = 1'b0;
        wr_pos_latched_q = '0;
        wr_target_q      = '0;
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
        illegal_q <= wr_conflict || guides_both || resetN_illegal_disabled ||
                     ga_too_long || gb_too_long ||
                     (wr_any_active && (guide_a_i || guide_b_i)) ||
                     (write_en_i && !is_onehot10(write_pos_i)) ||
                     write_pos_changed ||
                     !is_onehot30(cathodes_q);

        //--------------------------------------------------------------
        // Запись / сброс: удержание не менее MIN тактов переносит
        // разряд на целевой главный катод. Остальные главные катоды
        // на это время заблокированы.
        //--------------------------------------------------------------
        if (wr_any_active) begin
            move_timer_q <= '0;
            move_dir_q   <= MOVE_NONE;
            wr_active_q  <= 1'b1;

            if (write_en_i) wr_pos_latched_q <= write_pos_i;

            if (!wr_active_q || (wr_target_ring != wr_target_q)) begin
                // Начало новой операции. Смена цели без снятия воздействия
                // (например, импульс сброса в 0 сразу после сброса в 9)
                // — это тоже новая операция: отсчёт начинается заново.
                wr_target_q  <= wr_target_ring;
                wr_timer_q   <= CNT_W'(1);
                wr_settled_q <= 1'b0;
            end
            else if (!wr_settled_q) begin
                wr_timer_q <= wr_timer_q + CNT_W'(1);

                // Операция засчитывается ровно на MIN-м такте удержания;
                // повторного срабатывания каждый такт не происходит.
                if (!wr_conflict && wr_target_valid &&
                    ((wr_timer_q + CNT_W'(1)) >= wr_min_hs)) begin
                    cathodes_q   <= wr_target_q;
                    wr_settled_q <= 1'b1;
                end
            end
        end
        else begin
            // Воздействие снято
            wr_timer_q   <= '0;
            wr_settled_q <= 1'b0;
            wr_active_q  <= 1'b0;
            wr_target_q  <= '0;

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
            wr_target_q  <= '0;
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

    // Разряд стоит на главном катоде и внешних воздействий нет
    wire settled_on_main = on_main && !wr_any_active &&
                           !guide_a_i && !guide_b_i;

    assign main_onehot_o = settled_on_main ? main_decoded : 10'b0;

    generate
        if (EN_DEBUG_OUTPUTS) begin : g_dbg_on
            assign cathodes_dbg_o       = cathodes_q;
            assign on_guide_dbg_o       = on_ga || on_gb;
            assign moving_dbg_o         = (move_dir != MOVE_NONE);
            assign in_write_reset_dbg_o = wr_any_active;
            assign settled_dbg_o        = wr_any_active && wr_settled_q;
            assign invalid_dbg_o        = illegal_q || wr_conflict ||
                                          guides_both || resetN_illegal_disabled;
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

    //------------------------------------------------------------------
    // Assertions (TRS v0.1 §13)
    //------------------------------------------------------------------
`ifdef ASSERTIONS
    generate
        if (EN_ASSERTIONS) begin : g_assertions
            DekatronTubeV2_assertions #(
                .EN_RESETN (EN_RESETN)
            ) u_assertions (
                .hsClk       (hsClk),
                .guide_a_i   (guide_a_i),
                .guide_b_i   (guide_b_i),
                .write_en_i  (write_en_i),
                .write_pos_i (write_pos_i),
                .reset0_i    (reset0_i),
                .resetN_i    (resetN_i),
                .cathodes_q  (cathodes_q)
            );
        end
    endgenerate
`endif

endmodule

`default_nettype wire
