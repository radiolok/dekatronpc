//======================================================================
// DekatronTubeDelay — модель декатрона А110 без тактовой базы
//----------------------------------------------------------------------
// Та же кольцевая модель на 30 электродов, что и DekatronTubeV2, но
// длительности отрабатываются задержками #N в абсолютном времени, а не
// счётом тактов hsClk. Входа hsClk нет: как и настоящий прибор, модель
// реагирует только на уровни на своих электродах.
//
// Подключается вместо DekatronTubeV2 в DekatronModule при
// `define DEKATRON_DELAY_MODEL (только симуляция Icarus; Verilator и
// синтез используют DekatronTubeV2, в нетлисте модель — чёрный ящик).
//
//----------------------------------------------------------------------
// ПРИНЦИП
//
// Каждое воздействие — это «запрос» на один переход разряда:
//
//   канал подкатодов : {направление, положение разряда}, задержка GUIDE
//   канал сваливания : {направление, положение разряда}, задержка FALL
//   канал записи     : открытые катодные линии,          задержка WRITE
//
// Запрос проходит через непрерывное присваивание с задержкой. Оно
// инерционное: изменение правой части отменяет запланированное
// обновление. Поэтому значение доходит до выхода, только если запрос
// держался стабильно всё время задержки, а импульс короче задержки
// не делает ничего — ровно как в тактовой модели, где таймер
// перезапускается при смене запроса. Попутно отфильтровываются
// иголки нулевой длительности на подкатодных линиях (в нетлисте
// вентили переключаются в разных дельта-циклах).
//
// Положение разряда входит в запрос перемещения: после шага запрос
// обязательно меняется, и следующий шаг (например, с подкатода A на
// подкатод B) отсчитывается заново, а не сливается с предыдущим.
//
// Время задаётся в нс параметрами *_NS [TRS v0.25]: модель на задержках —
// это синтез и нетлист ламповой машины, hsClk в ней нет. Значения —
// макросы DEKATRON_*_NS из rtl/parameters.sv, их передаёт DekatronModule.
//
// `define DEKATRON_RANDOM_INIT: после включения питания разряд стоит на
// случайном главном катоде из LINES ($urandom), как у настоящего прибора
// (Harwell 1951: «the Dekatron tubes may light in any position»). Привести
// машину в известное состояние может только сброс по катодам
// (doc/harwell_1951_review.md §3). INIT_DIGIT тогда не действует.
//
// ЗАПИСЬ ПО КАТОДАМ [TRS v0.56]
//
// Вход записи — сами катодные линии line_open_i, как их видит прибор:
// 1 — лампа канала записи открыта, катод на −20 В и может гореть; 0 —
// лампа закрыта, катод на +150 В. Записи, сброса в 0 и сброса в верхнюю
// позицию в приборе нет, есть одно событие: если линия горящего катода
// закрыта не меньше WRITE_MIN, разряд гаснет и зажигается на
// единственной открытой линии. Открыта линия горящего катода — ничего не
// происходит. Открытых линий нет или больше одной — разряд зажигается
// где придётся: это ошибка схемы записи ($error), разряд остаётся.
// Какие линии закрыть, решает схема снаружи (DekatronCounter, платы
// записи и сброса, sch/logic/DEKATRON_A110/README.md §3.3).
//
// LINES — катоды, у которых есть цепь возврата. Катод без неё (выше
// MAX_DIGIT, TC-N1) гореть не может: его линия всегда 0, а случайное
// включение питания выбирает только среди LINES.
//======================================================================

`default_nettype none

module DekatronTubeDelay #(
    // Длительности, нс [TRS v0.25]: модель на задержках hsClk не знает.
    // DekatronModule передаёт макросы DEKATRON_*_NS (rtl/parameters.sv)
    parameter unsigned GUIDE_STEP_NS    = 200,
    parameter unsigned FALL_STEP_NS     = 1000,
    parameter unsigned GUIDE_MAX_NS     = 10000,
    parameter unsigned WRITE_MIN_NS     = 5000,
    parameter logic [9:0]  LINES            = 10'h3FF,
    parameter logic [3:0]  INIT_DIGIT       = 4'd0,
    parameter bit          INC_BY_A_THEN_B  = 1'b1,
    parameter bit          EN_SIM_PRESET    = 1'b1,
    parameter bit          EN_DEBUG_OUTPUTS = 1'b1
)(
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
`ifndef SYNTH
    // Задержки — в нс, независимо от `timescale тестбенча (Yosys этих
    // объявлений не знает, а модель для него — чёрный ящик)
    timeunit 1ns;
    timeprecision 1ps;
`endif
    // Длительности переходов, нс
    localparam int unsigned GUIDE_NS = GUIDE_STEP_NS;
    localparam int unsigned FALL_NS  = FALL_STEP_NS;
    localparam int unsigned GMAX_NS  = GUIDE_MAX_NS;
    localparam int unsigned WRITE_NS = WRITE_MIN_NS;

    localparam logic [29:0] MASK_MAIN = 30'b001001001001001001001001001001;
    localparam logic [29:0] MASK_GA   = 30'b010010010010010010010010010010;
    localparam logic [29:0] MASK_GB   = 30'b100100100100100100100100100100;

    localparam logic [1:0] MOVE_NONE = 2'd0;
    localparam logic [1:0] MOVE_FWD  = 2'd1;   // индекс +1
    localparam logic [1:0] MOVE_BACK = 2'd2;   // индекс -1

`ifndef SYNTH
    logic [29:0] cathodes_q;
    logic        illegal_q = 1'b0;

    initial begin
        cathodes_q = 30'd1 << (3*INIT_DIGIT);
`ifdef DEKATRON_RANDOM_INIT
        begin
            int unsigned d;
            d = $urandom % 10;
            while (!LINES[d]) d = $urandom % 10;
            cathodes_q = 30'd1 << (3*d);
        end
`endif
    end

    function automatic logic [29:0] main_to_ring(input logic [9:0] pos10);
        main_to_ring = 30'd0;
        for (int i = 0; i < 10; i++)
            if (pos10[i]) main_to_ring[3*i] = 1'b1;
    endfunction

    function automatic bit is_onehot10(input logic [9:0] v);
        is_onehot10 = (v != 10'd0) && ((v & (v - 10'd1)) == 10'd0);
    endfunction

    wire on_main = |(cathodes_q & MASK_MAIN);
    wire on_ga   = |(cathodes_q & MASK_GA);
    wire on_gb   = |(cathodes_q & MASK_GB);

    wire ga = INC_BY_A_THEN_B ? guide_a_i : guide_b_i;
    wire gb = INC_BY_A_THEN_B ? guide_b_i : guide_a_i;

    wire [9:0] main_now;
    genvar gi;
    for (gi = 0; gi < 10; gi++) begin : g_main_now
        assign main_now[gi] = cathodes_q[3*gi];
    end

    // Закрыта хоть одна линия: идёт запись, подкатоды должны молчать
    wire wr_any_active = |(~line_open_i & LINES);
    // Линия горящего катода закрыта: разряд обязан перейти. С подкатода
    // разряд, как и прежде, уходит на цель записи
    wire wr_needed     = on_main ? |(main_now & ~line_open_i) : wr_any_active;
    wire wr_target_ok  = is_onehot10(line_open_i & LINES);
    wire guides_both   = guide_a_i && guide_b_i;
    // Перекрытие фаз допустимо, пока разряд на подкатоде: он остаётся
    // там, пока не снята первая линия (см. DekatronTubeV2)
    wire guides_both_bad = guides_both && on_main;

    //------------------------------------------------------------------
    // Требуемое перемещение (та же таблица, что в DekatronTubeV2)
    //------------------------------------------------------------------
    logic [1:0] guide_dir;   // притяжение активным подкатодом
    logic [1:0] fall_dir;    // сваливание при снятых подкатодах

    always_comb begin
        guide_dir = MOVE_NONE;
        fall_dir  = MOVE_NONE;
        if (!wr_any_active && !guides_both) begin
            if (ga && !gb) begin
                if      (on_main) guide_dir = MOVE_FWD;    // 3k   -> 3k+1
                else if (on_gb)   guide_dir = MOVE_BACK;   // 3k+2 -> 3k+1
            end
            else if (gb && !ga) begin
                if      (on_main) guide_dir = MOVE_BACK;   // 3k   -> 3k-1
                else if (on_ga)   guide_dir = MOVE_FWD;    // 3k+1 -> 3k+2
            end
            else begin
                if      (on_ga)   fall_dir  = MOVE_BACK;   // 3k+1 -> 3k
                else if (on_gb)   fall_dir  = MOVE_FWD;    // 3k+2 -> 3k+3
            end
        end
    end

    //------------------------------------------------------------------
    // Инерционные задержки: выход равен входу, только если вход
    // продержался стабильно всю задержку
    //------------------------------------------------------------------
    wire [31:0] guide_req = {guide_dir, cathodes_q};
    wire [31:0] fall_req  = {fall_dir,  cathodes_q};
    wire [9:0]  write_req = line_open_i;

    wire [31:0] guide_req_d;
    wire [31:0] fall_req_d;
    wire [9:0]  write_req_d;

    assign #(GUIDE_NS) guide_req_d = guide_req;
    assign #(FALL_NS)  fall_req_d  = fall_req;
    assign #(WRITE_NS) write_req_d = write_req;

    function automatic logic [29:0] step(input logic [29:0] c,
                                         input logic [1:0]  dir);
        step = (dir == MOVE_FWD) ? {c[28:0], c[29]} : {c[0], c[29:1]};
    endfunction

    // Перемещение разряда на соседний электрод
    always @(guide_req_d)
        if (guide_req_d == guide_req && guide_dir != MOVE_NONE)
            cathodes_q = step(cathodes_q, guide_dir);

    always @(fall_req_d)
        if (fall_req_d == fall_req && fall_dir != MOVE_NONE)
            cathodes_q = step(cathodes_q, fall_dir);

    // Запись: линия горящего катода закрыта весь WRITE_MIN — разряд
    // переходит на единственную открытую линию
    always @(write_req_d)
        if (write_req_d === write_req && wr_needed === 1'b1) begin
            if (wr_target_ok)
                cathodes_q = main_to_ring(line_open_i);
            else begin
                illegal_q = 1'b1;
                $error("DekatronTubeDelay %m: lines %b: the burning cathode is closed, but not exactly one line is open",
                       line_open_i);
            end
        end

    always @(posedge sim_preset_en_i)
        if (EN_SIM_PRESET) cathodes_q = sim_preset_cathodes_i;

    //------------------------------------------------------------------
    // Диагностика недопустимых воздействий
    //------------------------------------------------------------------
    // Совпадения проверяются по истечении нулевой задержки, чтобы не
    // ловить иголки дельта-циклов в нетлисте
    wire [1:0] bad_now = {guides_both_bad,
                          wr_any_active && (guide_a_i || guide_b_i)};
    wire [1:0] bad_d;
    assign #1 bad_d = bad_now;

    always @(bad_d)
        if (|bad_d) begin
            illegal_q = 1'b1;
            $error("DekatronTubeDelay %m: illegal stimulus (both_guides=%b guide_in_write=%b)",
                   bad_d[1], bad_d[0]);
        end

    realtime ga_rise, gb_rise;
    always @(posedge guide_a_i) ga_rise = $realtime;
    always @(posedge guide_b_i) gb_rise = $realtime;
    always @(negedge guide_a_i)
        if ($realtime - ga_rise > GMAX_NS) begin
            illegal_q = 1'b1;
            $error("DekatronTubeDelay %m: guide A held %0t ns > GUIDE_MAX", $realtime - ga_rise);
        end
    always @(negedge guide_b_i)
        if ($realtime - gb_rise > GMAX_NS) begin
            illegal_q = 1'b1;
            $error("DekatronTubeDelay %m: guide B held %0t ns > GUIDE_MAX", $realtime - gb_rise);
        end

    //------------------------------------------------------------------
    // Выходы
    //------------------------------------------------------------------
    logic [9:0] main_decoded;
    always_comb
        for (int i = 0; i < 10; i++) main_decoded[i] = cathodes_q[3*i];

    // Линии чтения читаются всегда (см. DekatronTubeV2) [TRS v0.24]
    assign main_onehot_o = on_main ? main_decoded : 10'b0;

    generate
        if (EN_DEBUG_OUTPUTS) begin : g_dbg_on
            assign cathodes_dbg_o       = cathodes_q;
            assign on_guide_dbg_o       = on_ga || on_gb;
            assign moving_dbg_o         = (guide_dir != MOVE_NONE) ||
                                          (fall_dir  != MOVE_NONE);
            assign in_write_reset_dbg_o = wr_any_active;
            assign settled_dbg_o        = wr_any_active &&
                                          (write_req_d == write_req);
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

    initial begin
        if (LINES == 10'b0)
            $error("DekatronTubeDelay: LINES has no cathode");
        if (!LINES[INIT_DIGIT])
            $error("DekatronTubeDelay: INIT_DIGIT (%0d) has no line", INIT_DIGIT);
    end
`endif

endmodule

`default_nettype wire
