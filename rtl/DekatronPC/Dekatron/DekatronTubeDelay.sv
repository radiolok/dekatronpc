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
//   канал записи     : {write_en, позиция},              задержка WRITE
//   канал сброса     : {reset0, resetN},                 задержка RESET
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
// Время задаётся в нс: HS_NS — период временной базы, в которой
// выражены параметры *_HS (по умолчанию 100 нс, то есть 10 МГц, как
// hsClk). Параметры *_HS те же, что у DekatronTubeV2, поэтому
// DekatronModule и нетлист передают их без изменений.
//======================================================================

`default_nettype none

module DekatronTubeDelay #(
    parameter unsigned HS_PER_CLK       = 10,
    parameter unsigned WR_SYNC_HS       = HS_PER_CLK,
    parameter unsigned GUIDE_STEP_HS    = 2,
    parameter unsigned FALL_STEP_HS     = 3,
    parameter unsigned GUIDE_MAX_HS     = 20,
    parameter unsigned WRITE_MIN_HS     = 100,
    parameter unsigned RESET_MIN_HS     = 100,
    parameter bit          EN_RESETN        = 1'b0,
    parameter unsigned RESET_N_POS      = 9,
    parameter logic [3:0]  INIT_DIGIT       = 4'd0,
    parameter bit          INC_BY_A_THEN_B  = 1'b1,
    parameter bit          EN_SIM_PRESET    = 1'b1,
    parameter bit          EN_DEBUG_OUTPUTS = 1'b1,

    // Период временной базы параметров *_HS, нс
    parameter unsigned HS_NS            = 100
)(
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
`ifndef SYNTH
    // Задержки — в нс, независимо от `timescale тестбенча (Yosys этих
    // объявлений не знает, а модель для него — чёрный ящик)
    timeunit 1ns;
    timeprecision 1ps;
`endif
    // Длительности переходов, нс. Запись и сброс короче на задержку
    // квалификации запроса WR_SYNC_HS (см. DekatronTubeV2, wr_min_hs).
    localparam int unsigned GUIDE_NS = GUIDE_STEP_HS * HS_NS;
    localparam int unsigned FALL_NS  = FALL_STEP_HS  * HS_NS;
    localparam int unsigned GMAX_NS  = GUIDE_MAX_HS  * HS_NS;
    localparam int unsigned WRITE_NS =
        ((WRITE_MIN_HS > WR_SYNC_HS) ? (WRITE_MIN_HS - WR_SYNC_HS) : 1) * HS_NS;
    localparam int unsigned RESET_NS =
        ((RESET_MIN_HS > WR_SYNC_HS) ? (RESET_MIN_HS - WR_SYNC_HS) : 1) * HS_NS;

    localparam logic [29:0] MASK_MAIN = 30'b001001001001001001001001001001;
    localparam logic [29:0] MASK_GA   = 30'b010010010010010010010010010010;
    localparam logic [29:0] MASK_GB   = 30'b100100100100100100100100100100;

    localparam logic [1:0] MOVE_NONE = 2'd0;
    localparam logic [1:0] MOVE_FWD  = 2'd1;   // индекс +1
    localparam logic [1:0] MOVE_BACK = 2'd2;   // индекс -1

`ifndef SYNTH
    logic [29:0] cathodes_q = 30'd1 << (3*INIT_DIGIT);

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

    wire resetN_en     = EN_RESETN && resetN_i;
    wire wr_any_active = write_en_i || reset0_i || resetN_en;
    wire wr_conflict   = (write_en_i && reset0_i) ||
                         (write_en_i && resetN_en) ||
                         (reset0_i   && resetN_en);
    wire guides_both   = guide_a_i && guide_b_i;

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
    wire [10:0] write_req = {write_en_i, write_pos_i};
    wire [1:0]  reset_req = {resetN_en, reset0_i};

    wire [31:0] guide_req_d;
    wire [31:0] fall_req_d;
    wire [10:0] write_req_d;
    wire [1:0]  reset_req_d;

    assign #(GUIDE_NS) guide_req_d = guide_req;
    assign #(FALL_NS)  fall_req_d  = fall_req;
    assign #(WRITE_NS) write_req_d = write_req;
    assign #(RESET_NS) reset_req_d = reset_req;

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

    // Запись и сброс: разряд переносится на целевой главный катод
    always @(write_req_d)
        if (write_req_d == write_req && write_en_i && !wr_conflict) begin
            if (is_onehot10(write_pos_i))
                cathodes_q = main_to_ring(write_pos_i);
            else
                $error("DekatronTubeDelay %m: write_pos_i %b is not one-hot",
                       write_pos_i);
        end

    always @(reset_req_d)
        if (reset_req_d == reset_req && !wr_conflict) begin
            if (reset0_i)       cathodes_q = 30'd1;
            else if (resetN_en) cathodes_q = 30'd1 << (3*RESET_N_POS);
        end

    always @(posedge sim_preset_en_i)
        if (EN_SIM_PRESET) cathodes_q = sim_preset_cathodes_i;

    //------------------------------------------------------------------
    // Диагностика недопустимых воздействий
    //------------------------------------------------------------------
    logic illegal_q = 1'b0;

    // Совпадения проверяются по истечении нулевой задержки, чтобы не
    // ловить иголки дельта-циклов в нетлисте
    wire [2:0] bad_now = {wr_conflict, guides_both,
                          wr_any_active && (guide_a_i || guide_b_i)};
    wire [2:0] bad_d;
    assign #1 bad_d = bad_now;

    always @(bad_d)
        if (|bad_d) begin
            illegal_q = 1'b1;
            $error("DekatronTubeDelay %m: illegal stimulus (conflict=%b both_guides=%b guide_in_write=%b)",
                   bad_d[2], bad_d[1], bad_d[0]);
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

    wire settled_on_main = on_main && !wr_any_active &&
                           !guide_a_i && !guide_b_i;

    assign main_onehot_o = settled_on_main ? main_decoded : 10'b0;

    generate
        if (EN_DEBUG_OUTPUTS) begin : g_dbg_on
            assign cathodes_dbg_o       = cathodes_q;
            assign on_guide_dbg_o       = on_ga || on_gb;
            assign moving_dbg_o         = (guide_dir != MOVE_NONE) ||
                                          (fall_dir  != MOVE_NONE);
            assign in_write_reset_dbg_o = wr_any_active;
            assign settled_dbg_o        = wr_any_active &&
                                          (write_req_d == write_req) &&
                                          (reset_req_d == reset_req);
            assign invalid_dbg_o        = illegal_q || wr_conflict || guides_both;
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
        if (WRITE_MIN_HS <= WR_SYNC_HS)
            $error("DekatronTubeDelay: WRITE_MIN_HS (%0d) должен быть больше WR_SYNC_HS (%0d)",
                   WRITE_MIN_HS, WR_SYNC_HS);
        if (RESET_MIN_HS <= WR_SYNC_HS)
            $error("DekatronTubeDelay: RESET_MIN_HS (%0d) должен быть больше WR_SYNC_HS (%0d)",
                   RESET_MIN_HS, WR_SYNC_HS);
        if (!EN_RESETN && (RESET_N_POS > 9))
            $error("DekatronTubeDelay: RESET_N_POS (%0d) вне 0..9", RESET_N_POS);
    end
`endif

endmodule

`default_nettype wire
