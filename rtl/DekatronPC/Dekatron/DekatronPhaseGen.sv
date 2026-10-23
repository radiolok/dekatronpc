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
// `DEKATRON_DELAY_MODEL: та же схема, но OneShot/Impulse работают на
// задержках #N (см. их описание), и hsClk к ним не подводится вовсе —
// на вход Clk подаётся 0. Фазы отсчитываются от фронта Clk в абсолютном
// времени: PHASE1_HS * 100 нс и (PHASE1_HS + PHASE2_HS) * 100 нс.
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
    input  wire hsClk,    // временная база модели (10 МГц)
    input  wire Clk,      // такт счёта (1 МГц)
    input  wire Rst_n,    // модельный сброс элементов задержки

    output wire Phase1,
    output wire Phase2
);
`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
    timeunit 1ns;
    timeprecision 1ps;
`endif
`endif

    wire ClkRise;
    wire PhaseStart;  // начало первой фазы
    wire Win1;      // окно [0 .. PHASE1_HS)
    wire Win1Fall;  // спад Win1: начало второй фазы

    // Временная база элементов задержки. В модели на задержках её нет.
`ifdef DEKATRON_DELAY_MODEL
    wire tClk = 1'b0;
`else
    wire tClk = hsClk;
`endif

    // Начало такта счёта
    Impulse clkRiseDet (
        .Clk     (tClk),
        .Rst_n   (Rst_n),
        .En      (Clk),
        .Impulse (ClkRise)
    );

    // Задержка начала фаз: окно от фронта Clk, фазы — от его спада
    generate
        if (PHASE_DELAY_HS > 0) begin : g_delay
            wire WinDelay;

            OneShot #(
                .DELAY (PHASE_DELAY_HS)
            ) osDelay (
                .Clk     (tClk),
                .Rst_n   (Rst_n),
                .En      (ClkRise),
                .Impulse (WinDelay)
            );

            Impulse #(
                .FALL (1'b1)
            ) delayEndDet (
                .Clk     (tClk),
                .Rst_n   (Rst_n),
                .En      (WinDelay),
                .Impulse (PhaseStart)
            );
        end
        else begin : g_no_delay
            assign PhaseStart = ClkRise;
        end
    endgenerate

    // Первая фаза
    OneShot #(
        .DELAY (PHASE1_HS)
    ) osPhase1 (
        .Clk     (tClk),
        .Rst_n   (Rst_n),
        .En      (PhaseStart),
        .Impulse (Win1)
    );

    // Вторая фаза — окно от спада первой, встык без зазора
    Impulse #(
        .FALL (1'b1)
    ) win1FallDet (
        .Clk     (tClk),
        .Rst_n   (Rst_n),
        .En      (Win1),
        .Impulse (Win1Fall)
    );

    OneShot #(
        .DELAY (PHASE2_HS)
    ) osPhase2 (
        .Clk     (tClk),
        .Rst_n   (Rst_n),
        .En      (Win1Fall),
        .Impulse (Phase2)
    );

    assign Phase1 = Win1;

`ifndef SYNTH
    initial begin
        if (PHASE1_HS == 0 || PHASE2_HS == 0)
            $error("DekatronPhaseGen: PHASE1_HS and PHASE2_HS must be > 0");
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
