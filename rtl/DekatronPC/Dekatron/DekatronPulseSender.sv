//======================================================================
// DekatronPulseSender — формирователь подкатодных импульсов
//----------------------------------------------------------------------
// Такт счёта нарезан на три части (см. DekatronPhaseGen):
//
//   первая треть  — импульс на первом подкатоде
//   вторая треть  — импульс на втором подкатоде
//   третья треть  — обе линии сняты, разряд сваливается на соседний
//                   главный катод
//
// Направление счёта меняет порядок фаз:
//
//   StepF (вперёд): GuideA = Phase1, GuideB = Phase2
//   StepR (назад):  GuideA = Phase2, GuideB = Phase1
//
// Сам модуль — чистая комбинаторика: 4 элемента И и 2 элемента ИЛИ.
// Времязадающая часть вынесена в DekatronPhaseGen и может быть общей
// на весь многоразрядный счётчик.
//
//----------------------------------------------------------------------
// ПОЧЕМУ ТРИ ФАЗЫ, А НЕ ПОЛУВОЛНЫ
//
// При делении такта на две полуволны разряд к концу такта остаётся на
// втором подкатоде, и первая фаза следующего такта утаскивает его
// обратно: разряд бесконечно колеблется между подкатодами и не попадает
// на главный катод вообще. Чтобы шаг завершился, требовалась пауза
// длиной в целый такт, то есть счёт через такт — 500 кГц.
//
// Третья треть даёт разряду упасть на катод внутри того же такта,
// поэтому счёт идёт КАЖДЫЙ такт: 1 МГц при Clk = 1 МГц.
//
//----------------------------------------------------------------------
// ТРЕБОВАНИЯ К ВЫШЕСТОЯЩЕМУ СЧЁТЧИКУ
//
//   * StepF/StepR удерживаются весь такт и переключаются по фронту Clk.
//     Снятие запроса в середине такта оставит разряд на подкатоде.
//   * Одновременная подача StepF и StepR недопустима.
//   * Показание достоверно только к концу такта, когда разряд сел на
//     главный катод (признак Valid у DekatronModule).
//======================================================================

`default_nettype none

module DekatronPulseSender #(
    // 0 — генератор фаз внутри модуля (автономный режим)
    // 1 — фазы приходят снаружи, общие на весь счётчик (экономия ламп)
    parameter bit          EXT_PHASES = 1'b0,

    parameter unsigned PHASE1_HS  = 3,
    parameter unsigned PHASE2_HS  = 4
)(
    input  wire hsClk,      // временная база модели
    input  wire Clk,        // такт счёта
    input  wire Rst_n,      // модельный сброс элементов задержки

    // Запросы шага. Одновременная активация недопустима.
    input  wire StepF,      // шаг вперёд  (инкремент)
    input  wire StepR,      // шаг назад   (декремент)

    // Внешние фазы, используются только при EXT_PHASES = 1
/* verilator lint_off UNUSEDSIGNAL */
    input  wire Phase1_i,
    input  wire Phase2_i,
/* verilator lint_on UNUSEDSIGNAL */

    // Подкатодные линии на декатрон
    output wire GuideA,
    output wire GuideB
);

    wire Phase1;
    wire Phase2;

    //------------------------------------------------------------------
    // Источник фаз
    //------------------------------------------------------------------
    generate
        if (EXT_PHASES) begin : g_ext_phases
            assign Phase1 = Phase1_i;
            assign Phase2 = Phase2_i;
        end
        else begin : g_own_phases
            DekatronPhaseGen #(
                .PHASE1_HS (PHASE1_HS),
                .PHASE2_HS (PHASE2_HS)
            ) phaseGen (
                .hsClk  (hsClk),
                .Clk    (Clk),
                .Rst_n  (Rst_n),
                .Phase1 (Phase1),
                .Phase2 (Phase2)
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // Разводка фаз по подкатодам в зависимости от направления
    //------------------------------------------------------------------
    wire fwdA, fwdB;
    wire revA, revB;

    and u_fwd_a (fwdA, StepF, Phase1);
    and u_fwd_b (fwdB, StepF, Phase2);

    and u_rev_a (revA, StepR, Phase2);
    and u_rev_b (revB, StepR, Phase1);

    or  u_guide_a (GuideA, fwdA, revA);
    or  u_guide_b (GuideB, fwdB, revB);

`ifndef SYNTH
    always @(posedge hsClk or negedge Rst_n) begin
        if (~Rst_n) begin

        end else if (StepF && StepR)
            $error("DekatronPulseSender: StepF and StepR asserted simultaneously");
    end
`endif

endmodule

`default_nettype wire
