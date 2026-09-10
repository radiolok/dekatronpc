//======================================================================
// DekatronModule — декатронный модуль
//----------------------------------------------------------------------
// Состав (все вложенные блоки — отдельные инстансы, на этапе P&R
// заменяются базовыми ламповыми ячейками):
//
//   DekatronTubeV2     — сам декатрон (всегда)
//   DekatronPulseSender— формирователь подкатодных импульсов (всегда)
//   DekatronPhaseGen   — нарезка такта на трети (внутри PulseSender либо
//                        общая на весь счётчик, см. EXT_PHASES)
//   BcdToOneHotEn      — преобразователь 8-4-2-1 -> позиционный, по WRITE
//   BinToBcd           — преобразователь позиционный -> 8-4-2-1, по READ
//
//----------------------------------------------------------------------
// ЧТО ИЗМЕНИЛОСЬ ОТНОСИТЕЛЬНО ПРЕЖНЕЙ ВЕРСИИ
//
// 1. Исчезла сборка InPosDek_n из Set[2:0]. Прежде линии сброса в нуль
//    и в верхнюю позицию подмешивались в шину записи катодов вручную,
//    внутри generate-блоков. Теперь у модели декатрона есть выделенные
//    физические входы reset0_i и resetN_i, поэтому SetZero и SetTop
//    идут на них напрямую. Ветвление по WRITE стало тривиальным.
//
// 2. Исчез приём с маскированием выхода в X:
//        OutPos = (~(|_OutPos) | (|Pulses)) ? 10'bx : _OutPos;
//    Модель декатрона сама выдаёт нулевой позиционный код, пока разряд
//    не установился на главном катоде. Вместо неопределённости — явный
//    сигнал Valid, физически реализуемый как ИЛИ по линиям чтения.
//
// 3. Формирователь импульсов перестроен: такт счёта делится на трети —
//    первый подкатод, второй подкатод, пауза на сваливание разряда.
//    Пауза внутри такта позволяет считать каждый такт (1 МГц), а не
//    через такт. Времязадающие элементы вынесены в DekatronPhaseGen и
//    моделируют RC-цепи реальной схемы.
//
//----------------------------------------------------------------------
// ТАКТИРОВАНИЕ
//
//   hsClk — временная база модели декатрона (10 МГц). Только для модели:
//           в железе декатрон отрабатывает длительности сам.
//   Clk   — тактовая частота счёта (1 МГц). Её полуволны образуют фазы
//           подкатодов, поэтому каждая фаза длится 5 тактов hsClk.
//
//----------------------------------------------------------------------
// ПРАВИЛА ДЛЯ ВЫШЕСТОЯЩЕГО СЧЁТЧИКА
//
//   * Один шаг — одна активация StepF/StepR на период Clk. Пауза на
//     сваливание разряда заложена внутрь такта (третья треть), поэтому
//     шаги можно выдавать подряд каждый такт.
//   * StepF/StepR переключаются по фронту Clk и держатся весь такт.
//     Снятие запроса в середине такта оставит разряд на подкатоде.
//   * Показание Out достоверно только при Valid = 1.
//   * SetData/SetZero/SetTop удерживаются не менее WRITE_MIN_HS /
//     RESET_MIN_HS тактов hsClk, иначе операция не состоится.
//   * Одновременная подача нескольких воздействий недопустима.
//======================================================================

`default_nettype none

(* keep_hierarchy = "yes" *)
module DekatronModule #(
    // Состав обвязки
    parameter bit          READ            = 1'b1,   // ставить BinToBcd
    parameter bit          WRITE           = 1'b1,   // ставить BcdToOneHotEn

    // Верхний предел счёта
    parameter bit          TOP_LIMIT_MODE  = 1'b1,   // выводить TopPin и SetTop
    parameter unsigned TOP_PIN_OUT     = 9,      // номер верхней позиции

    // Начальное положение разряда после включения питания
    parameter logic [3:0]  INIT_DIGIT      = 4'd0,

    // Временные характеристики декатрона (такты hsClk)
    parameter unsigned GUIDE_STEP_HS   = 2,
    parameter unsigned FALL_STEP_HS    = 3,
    parameter unsigned GUIDE_MAX_HS    = 20,
    parameter unsigned WRITE_MIN_HS    = 100,
    parameter unsigned RESET_MIN_HS    = 100,

    // Нарезка такта счёта на трети (такты hsClk)
    parameter unsigned HS_PER_CLK      = 10,
    parameter unsigned PHASE1_HS       = 3,
    parameter unsigned PHASE2_HS       = 4,

    // 1 — фазы приходят снаружи, один генератор на весь счётчик
    parameter bit          EXT_PHASES      = 1'b0,

    // Порядок фаз, дающий инкремент
    parameter bit          INC_BY_A_THEN_B = 1'b1,

    parameter bit          EN_ASSERTIONS   = 1'b1
)(
    input  wire       hsClk,     // временная база модели декатрона
    input  wire       Clk,       // тактовая частота счёта
    input  wire       Rst_n,     // модельный сброс элементов задержки

    // Счёт
    input  wire       StepF,     // шаг вперёд
    input  wire       StepR,     // шаг назад

    // Внешние фазы, только при EXT_PHASES = 1
/* verilator lint_off UNUSEDSIGNAL */
    input  wire       Phase1_i,
    input  wire       Phase2_i,
/* verilator lint_on UNUSEDSIGNAL */

    // Установка значения
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [3:0] In,        // записываемое число, 8-4-2-1
    input  wire       SetData,   // запись числа со входа In (только при WRITE)
    input  wire       SetTop,    // сброс в позицию TOP_PIN_OUT (при TOP_LIMIT_MODE)
/* verilator lint_on UNUSEDSIGNAL */
    input  wire       SetZero,   // сброс в нуль

    // Чтение
    output wire [3:0] Out,       // текущее число, 8-4-2-1 (только при READ)
    output wire       Valid,     // показание достоверно

    // Признаки позиций для схемы переноса
    output wire       Zero,      // разряд на нулевом катоде
    output wire       Nine,      // разряд на девятом катоде
    output wire       TopPin     // разряд на катоде TOP_PIN_OUT
);

    //------------------------------------------------------------------
    // Внутренние связи
    //------------------------------------------------------------------
    wire [9:0] MainOneHot;      // позиционный код с главных катодов
    wire [9:0] WritePos;        // позиционный код на усилители записи
    wire       GuideA;
    wire       GuideB;

    //------------------------------------------------------------------
    // Формирователь подкатодных фаз
    //------------------------------------------------------------------
    DekatronPulseSender #(
        .EXT_PHASES (EXT_PHASES),
        .PHASE1_HS  (PHASE1_HS),
        .PHASE2_HS  (PHASE2_HS)
    ) pulseSender (
        .hsClk    (hsClk),
        .Clk      (Clk),
        .Rst_n    (Rst_n),
        .StepF    (StepF),
        .StepR    (StepR),
        .Phase1_i (Phase1_i),
        .Phase2_i (Phase2_i),
        .GuideA   (GuideA),
        .GuideB   (GuideB)
    );

    //------------------------------------------------------------------
    // Схема записи — только при WRITE.
    // Это самая дорогая по лампам часть обвязки, поэтому в счётчиках
    // без записи она не ставится вовсе.
    //------------------------------------------------------------------
    wire WriteEn;

    generate
        if (WRITE) begin : g_write
            BcdToBinEn bcdToOneHot (
                .In  (In),
                .En  (SetData),
                .Out (WritePos)
            );
            assign WriteEn = SetData;
        end
        else begin : g_no_write
            assign WritePos = 10'b0;
            assign WriteEn  = 1'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // Сброс в верхнюю позицию — только при TOP_LIMIT_MODE.
    // В модели декатрона это линия resetN с параметром RESET_N_POS.
    //------------------------------------------------------------------
    wire ResetTop;

    generate
        if (TOP_LIMIT_MODE) begin : g_top_set
            assign ResetTop = SetTop;
        end
        else begin : g_no_top_set
            assign ResetTop = 1'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // Декатрон
    //------------------------------------------------------------------
    DekatronTubeV2 #(
        //.HS_PER_CLK       (10),
        .GUIDE_STEP_HS    (GUIDE_STEP_HS),
        .FALL_STEP_HS     (FALL_STEP_HS),
        .GUIDE_MAX_HS     (GUIDE_MAX_HS),
        .WRITE_MIN_HS     (WRITE_MIN_HS),
        //.WRITE_MAX_HS     (2*WRITE_MIN_HS),
        .RESET_MIN_HS     (RESET_MIN_HS),
        //.RESET_MAX_HS     (2*RESET_MIN_HS),
        .EN_RESETN        (TOP_LIMIT_MODE),
        .RESET_N_POS      (TOP_PIN_OUT),
        .INIT_DIGIT       (INIT_DIGIT),
        .INC_BY_A_THEN_B  (INC_BY_A_THEN_B),
        .EN_SIM_PRESET    (1'b0),
        .EN_ASSERTIONS    (EN_ASSERTIONS),
        .EN_DEBUG_OUTPUTS (1'b0)
    ) dekatron (
        .hsClk                 (hsClk),
        .guide_a_i             (GuideA),
        .guide_b_i             (GuideB),
        .write_en_i            (WriteEn),
        .write_pos_i           (WritePos),
        .reset0_i              (SetZero),
        .resetN_i              (ResetTop),
        .sim_preset_en_i       (1'b0),
        .sim_preset_cathodes_i (30'b0),
        .main_onehot_o         (MainOneHot),
        //verilator lint_off PINCONNECTEMPTY
        .cathodes_dbg_o        (),
        .on_guide_dbg_o        (),
        .moving_dbg_o          (),
        .in_write_reset_dbg_o  (),
        .settled_dbg_o         (),
        .invalid_dbg_o         ()
        //verilator lint_on PINCONNECTEMPTY
    );

    //------------------------------------------------------------------
    // Схема чтения — только при READ
    //------------------------------------------------------------------
    generate
        if (READ) begin : g_read
            BinToBcd binToBcd (
                .In  (MainOneHot),
                .Out (Out)
            );
        end
        else begin : g_no_read
            assign Out = 4'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // Признак достоверности показания.
    // Ставится всегда: без него нельзя отличить «разряд на нулевом
    // катоде» от «разряд ещё в пути».
    //------------------------------------------------------------------

    assign Valid = |MainOneHot;

    //------------------------------------------------------------------
    // Признаки позиций для схемы переноса.
    // Отводы прямо с линий чтения главных катодов, ламп не требуют.
    //------------------------------------------------------------------
    assign Zero = MainOneHot[0];
    assign Nine = MainOneHot[9];

    generate
        if (TOP_LIMIT_MODE) begin : g_top_pin
            assign TopPin = MainOneHot[TOP_PIN_OUT];
        end
        else begin : g_no_top_pin
            assign TopPin = 1'b0;
        end
    endgenerate

`ifndef SYNTH
    initial begin
        // Фазы обязаны вмещать переход разряда на подкатод
        if (PHASE1_HS < GUIDE_STEP_HS)
            $error("DekatronModule: PHASE1_HS (%0d) < GUIDE_STEP_HS (%0d): разряд не успеет уйти на подкатод",
                   PHASE1_HS, GUIDE_STEP_HS);
        if (PHASE2_HS < GUIDE_STEP_HS)
            $error("DekatronModule: PHASE2_HS (%0d) < GUIDE_STEP_HS (%0d): разряд не успеет уйти на второй подкатод",
                   PHASE2_HS, GUIDE_STEP_HS);

        // Третья треть обязана вмещать сваливание на главный катод.
        // Иначе разряд останется на подкатоде и счёта не будет вовсе:
        // показание никогда не станет достоверным.
        if ((HS_PER_CLK - PHASE1_HS - PHASE2_HS) < FALL_STEP_HS)
            $error("DekatronModule: окно сваливания (%0d) < FALL_STEP_HS (%0d): счёт не пойдёт",
                   HS_PER_CLK - PHASE1_HS - PHASE2_HS, FALL_STEP_HS);

        if ((PHASE1_HS + PHASE2_HS) >= HS_PER_CLK)
            $error("DekatronModule: фазы занимают весь такт, окна сваливания не остаётся");

        if (TOP_PIN_OUT > 9)
            $error("DekatronModule: TOP_PIN_OUT (%0d) must be in range 0..9",
                   TOP_PIN_OUT);
        if (TOP_LIMIT_MODE && !WRITE && (TOP_PIN_OUT == 0))
            $warning("DekatronModule: TOP_PIN_OUT = 0 duplicates SetZero");
    end
`endif

endmodule

`default_nettype wire
