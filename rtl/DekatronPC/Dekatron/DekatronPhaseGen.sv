//======================================================================
// DekatronPhaseGen — нарезка такта счёта на три фазы
//----------------------------------------------------------------------
// Такт Clk делится на три интервала (D = PHASE_DELAY_HS):
//
//   [D .. D+PHASE1_HS)                    — Phase1: первый подкатод
//   [D+PHASE1_HS .. D+PHASE1_HS+PHASE2_HS) — Phase2: второй подкатод
//   [D+PHASE1_HS+PHASE2_HS .. HS_PER_CLK) — обе линии сняты, разряд
//                                           сваливается на соседний
//                                           главный катод
//
// ЗАДЕРЖКА НАЧАЛА ФАЗ (REQ-PULSE-009, doc/vtube_sdf_timing.md §3.1)
//
// Команда шага (StepF/StepR) и разрешения декад En приходят от триггеров
// и вентилей, то есть позже фронта Clk. Фазы обязаны начинаться, когда
// команда уже установилась и когда команда прошлого такта уже снята.
// Иначе первая фаза пройдёт мимо шага, а хвост команды прошлого такта
// попадёт на фазы этого. PHASE_DELAY_HS — это ещё одна RC-цепь перед
// первой фазой, и она должна быть не короче худшего пути команды от фронта
// Clk. В RTL вентили без задержки, поэтому по умолчанию 0. Для нетлиста с
// задержками ламп значение задаёт synth_sim.sh -t.
//
// Третий интервал — обязательный. Без него разряд остаётся на подкатоде
// и следующая фаза утащит его обратно: счёта не будет вовсе. Именно эта
// пауза позволяет считать КАЖДЫЙ такт, а не через один.
//
// СТЫК ФАЗ (doc/harwell_1951_review.md §2)
//
// Между первой и второй фазой не должно быть зазора: без линий разряд
// начинает сваливаться с подкатода назад. Перекрытие допустимо и в
// железе неизбежно (фронты RC-цепей), модель декатрона его принимает.
// Поэтому вторую фазу запускает спад первой (Impulse с FALL = 1), а не
// вентили: прежнее Phase2 = Win12 & ~Win1 в нетлисте начиналось на
// 150 нс позже конца Phase1 (NOT + AND, doc/vtube_sdf_timing.md §3.2).
// Обе фазы выходят прямо из времязадающих элементов, вентилей нет.
//
//----------------------------------------------------------------------
// СООТВЕТСТВИЕ РЕАЛЬНОЙ СХЕМЕ
//
// В железе интервалы задаются не счётчиками, а RC-цепями: заряд
// разделительных конденсаторов формирует импульсы нужной длительности
// и амплитуды, как в схеме реверсивной декатронной декады у Яблонского.
// Здесь эти задержки моделируются элементами OneShot по временной базе
// hsClk. При переходе к физическому синтезу OneShot заменяется реальной
// времязадающей цепью, а Rst_n исчезает — это чисто модельный сигнал
// начальной установки счётчиков задержки.
//
// `DEKATRON_DELAY_MODEL (синтез и нетлист ламповой машины): та же схема,
// но OneShot/Impulse — RC-цепи на задержках #N, порта hsClk нет вовсе
// [TRS v0.25]. Длительности в нс задают макросы DEKATRON_PHASE_DELAY_NS,
// DEKATRON_PHASE1_NS, DEKATRON_PHASE2_NS и DEKATRON_EDGE_NS (импульс
// дифференцирующей цепи), rtl/parameters.sv; параметры *_HS — только для
// тактовой модели.
//
//----------------------------------------------------------------------
// ЭКОНОМИЯ ЛАМП
//
// Генератор общий для всего многоразрядного счётчика: фазы одинаковы
// для всех декатронов, а какой именно разряд шагает — определяют
// вентили в DekatronPulseSender. Поэтому в счётчике ставится ОДИН
// DekatronPhaseGen, а модули подключаются с EXT_PHASES = 1.
//======================================================================

`default_nettype none

module DekatronPhaseGen #(
    parameter unsigned PHASE1_HS      = 3,  // длительность первой фазы
    parameter unsigned PHASE2_HS      = 3,  // длительность второй фазы
    parameter unsigned PHASE_DELAY_HS = 0   // задержка начала фаз от фронта Clk
)(
`ifndef DEKATRON_DELAY_MODEL
    input  wire hsClk,    // временная база тактовой модели (10 × Clk)
`endif
    input  wire Clk,      // такт счёта
    input  wire Rst_n,    // модельный сброс элементов задержки

    output wire Phase1,
    output wire Phase2,
    // Окно команды: от фронта Clk до начала первой фазы. Пока оно поднято,
    // разряды стоят, и защёлки разрешений декад DekatronCounter прозрачны;
    // на фазы и сваливание они закрыты (doc/tube_count_1000.md §3)
    output wire CmdWin
);
`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
    timeunit 1ns;
    timeprecision 1ps;
`endif
`endif

    wire ClkRise;
    wire PhaseStart;  // начало первой фазы
    wire Win1;      // окно первой фазы
    wire Win1Fall;  // спад Win1: начало второй фазы

    // Длительности. Тактовая модель (FPGA, симуляция без задержек) —
    // такты hsClk из параметров *_HS. Модель на задержках (синтез и
    // нетлист ламповой машины) — RC-цепи в нс из макросов
    // DEKATRON_PHASE*_NS (rtl/parameters.sv), hsClk нет [TRS v0.25]
`ifdef DEKATRON_DELAY_MODEL
    localparam int unsigned DELAY_NS  = `DEKATRON_PHASE_DELAY_NS;
    localparam int unsigned PHASE1_NS = `DEKATRON_PHASE1_NS;
    localparam int unsigned PHASE2_NS = `DEKATRON_PHASE2_NS;
    localparam int unsigned EDGE_NS   = `DEKATRON_EDGE_NS;
    localparam bit          HAS_DELAY = (DELAY_NS > 0);
`else
    localparam bit          HAS_DELAY = (PHASE_DELAY_HS > 0);
`endif

    // Начало такта счёта
    Impulse
`ifdef DEKATRON_DELAY_MODEL
    #(.WIDTH_NS (EDGE_NS))
`endif
    clkRiseDet (
`ifndef DEKATRON_DELAY_MODEL
        .Clk     (hsClk),
`endif
        .Rst_n   (Rst_n),
        .En      (Clk),
        .Impulse (ClkRise)
    );

    // Задержка начала фаз: окно от фронта Clk, фазы — от его спада
    generate
        if (HAS_DELAY) begin : g_delay
            wire WinDelay;

            OneShot #(
`ifdef DEKATRON_DELAY_MODEL
                .DELAY_NS (DELAY_NS)
`else
                .DELAY    (PHASE_DELAY_HS)
`endif
            ) osDelay (
`ifndef DEKATRON_DELAY_MODEL
                .Clk     (hsClk),
`endif
                .Rst_n   (Rst_n),
                .En      (ClkRise),
                .Impulse (WinDelay)
            );
            assign CmdWin = WinDelay;

            Impulse #(
`ifdef DEKATRON_DELAY_MODEL
                .WIDTH_NS (EDGE_NS),
`endif
                .FALL (1'b1)
            ) delayEndDet (
`ifndef DEKATRON_DELAY_MODEL
                .Clk     (hsClk),
`endif
                .Rst_n   (Rst_n),
                .En      (WinDelay),
                .Impulse (PhaseStart)
            );
        end
        else begin : g_no_delay
            assign PhaseStart = ClkRise;
            assign CmdWin     = ClkRise;
        end
    endgenerate

    // Первая фаза
    OneShot #(
`ifdef DEKATRON_DELAY_MODEL
        .DELAY_NS (PHASE1_NS)
`else
        .DELAY    (PHASE1_HS)
`endif
    ) osPhase1 (
`ifndef DEKATRON_DELAY_MODEL
        .Clk     (hsClk),
`endif
        .Rst_n   (Rst_n),
        .En      (PhaseStart),
        .Impulse (Win1)
    );

    // Вторая фаза — окно от спада первой, встык без зазора
    Impulse #(
`ifdef DEKATRON_DELAY_MODEL
        .WIDTH_NS (EDGE_NS),
`endif
        .FALL (1'b1)
    ) win1FallDet (
`ifndef DEKATRON_DELAY_MODEL
        .Clk     (hsClk),
`endif
        .Rst_n   (Rst_n),
        .En      (Win1),
        .Impulse (Win1Fall)
    );

    OneShot #(
`ifdef DEKATRON_DELAY_MODEL
        .DELAY_NS (PHASE2_NS)
`else
        .DELAY    (PHASE2_HS)
`endif
    ) osPhase2 (
`ifndef DEKATRON_DELAY_MODEL
        .Clk     (hsClk),
`endif
        .Rst_n   (Rst_n),
        .En      (Win1Fall),
        .Impulse (Phase2)
    );

    assign Phase1 = Win1;

`ifndef SYNTH
    initial begin
`ifdef DEKATRON_DELAY_MODEL
        if (PHASE1_NS == 0 || PHASE2_NS == 0)
            $error("DekatronPhaseGen: DEKATRON_PHASE1_NS and DEKATRON_PHASE2_NS must be > 0");
`else
        if (PHASE1_HS == 0 || PHASE2_HS == 0)
            $error("DekatronPhaseGen: PHASE1_HS and PHASE2_HS must be > 0");
`endif
    end

    // Зазора между фазами быть не должно: вторая поднята к спаду первой.
    // Перекрытие допустимо (см. шапку).
`ifdef DEKATRON_DELAY_MODEL
    // Без тактовой базы: проверка сразу после спада, кроме иголок
    // нулевой длительности (дельта-циклы нетлиста)
    always @(negedge Phase1)
        if (Rst_n) #0.001 if (Rst_n && !Phase2)
            $error("DekatronPhaseGen: gap between Phase1 and Phase2");
`else
    logic phase1_q;
    always @(posedge hsClk or negedge Rst_n) begin
        if (~Rst_n)
            phase1_q <= 1'b0;
        else begin
            if (phase1_q && !Phase1 && !Phase2)
                $error("DekatronPhaseGen: gap between Phase1 and Phase2");
            phase1_q <= Phase1;
        end
    end
`endif
`endif

endmodule

`default_nettype wire
