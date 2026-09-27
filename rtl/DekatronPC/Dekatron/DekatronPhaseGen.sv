//======================================================================
// DekatronPhaseGen — нарезка такта счёта на три фазы
//----------------------------------------------------------------------
// Такт Clk делится на три интервала:
//
//   [0 .. PHASE1_HS)                      — Phase1: первый подкатод
//   [PHASE1_HS .. PHASE1_HS+PHASE2_HS)    — Phase2: второй подкатод
//   [PHASE1_HS+PHASE2_HS .. HS_PER_CLK)   — обе линии сняты, разряд
//                                           сваливается на соседний
//                                           главный катод
//
// Третий интервал — обязательный. Без него разряд остаётся на подкатоде
// и следующая фаза утащит его обратно: счёта не будет вовсе. Именно эта
// пауза позволяет считать КАЖДЫЙ такт, а не через один.
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
    parameter unsigned PHASE1_HS = 3,   // длительность первой фазы
    parameter unsigned PHASE2_HS = 4    // длительность второй фазы
)(
    input  wire hsClk,    // временная база модели (10 МГц)
    input  wire Clk,      // такт счёта (1 МГц)
    input  wire Rst_n,    // модельный сброс элементов задержки

    output wire Phase1,
    output wire Phase2
);

    localparam int unsigned PHASE12_HS = PHASE1_HS + PHASE2_HS;

    wire ClkRise;
    wire Win1;      // окно [0 .. PHASE1_HS)
    wire Win12;     // окно [0 .. PHASE1_HS+PHASE2_HS)
    wire Win1_n;

    // Начало такта счёта
    Impulse clkRiseDet (
        .Clk     (hsClk),
        .Rst_n   (Rst_n),
        .En      (Clk),
        .Impulse (ClkRise)
    );

    // Два вложенных окна от начала такта
    OneShot #(
        .DELAY (PHASE1_HS)
    ) osPhase1 (
        .Clk     (hsClk),
        .Rst_n   (Rst_n),
        .En      (ClkRise),
        .Impulse (Win1)
    );

    OneShot #(
        .DELAY (PHASE12_HS)
    ) osPhase12 (
        .Clk     (hsClk),
        .Rst_n   (Rst_n),
        .En      (ClkRise),
        .Impulse (Win12)
    );

    // Вторая фаза — разность окон
    not u_win1_inv (Win1_n, Win1);
    and u_phase2   (Phase2, Win12, Win1_n);

    assign Phase1 = Win1;

`ifndef SYNTH
    initial begin
        if (PHASE1_HS == 0 || PHASE2_HS == 0)
            $error("DekatronPhaseGen: PHASE1_HS and PHASE2_HS must be > 0");
    end

    // Фазы не должны перекрываться ни при каких условиях
    always @(posedge hsClk or negedge Rst_n) begin
        if (~Rst_n) begin

        end else if (Phase1 && Phase2)
            $error("DekatronPhaseGen: Phase1 and Phase2 overlap");
    end
`endif

endmodule

`default_nettype wire
