//======================================================================
// DekatronModule — декатронный модуль
//----------------------------------------------------------------------
// Состав (все вложенные блоки — отдельные инстансы, на этапе P&R
// заменяются базовыми ламповыми ячейками):
//
//   DekatronTubeV2     — сам декатрон (всегда)
//   GUIDE_EN_J2 × 2    — ключи подкатодов A и B (всегда), по лампе J2
//                        на подкатод: пентод с двумя управляющими
//                        сетками, на одной импульс шины GuideA/GuideB
//                        счётчика, на другой En
//   WRCH_N16           — каналы записи (лампы в катодных цепях) по
//                        перемычкам платы: полная запись, сброс в 0,
//                        сброс в 0/TOP
//   BinToBcdN          — преобразователь позиционный -> 8-4-2-1 активным
//                        нулём (ИЛИ-НЕ без инверторов, TC-O3), по READ
//
//----------------------------------------------------------------------
// ЧТО ИЗМЕНИЛОСЬ ОТНОСИТЕЛЬНО ПРЕЖНЕЙ ВЕРСИИ
//
// 1. [TRS v0.56] Запись — по катодным линиям. Модуль получает уровни
//    LineOpen[9:0] (линии W0…W9 через разъём, sch/logic/DEKATRON_A110/
//    README.md §3.3): 1 — лампа канала записи открыта, катод на −20 В;
//    0 — закрыта. В покое все линии 1. Для записи цифры i схема снаружи
//    держит открытой только линию i: открыта_i = ¬W ∨ sel_i. Сброс в 0 и
//    в TOP — то же самое. Дешифратор записи и уровни сброса формирует
//    DekatronCounter (клей блока, doc/board_estimate.md §2.6), модуль
//    лишь разводит линии по каналам записи своей платы:
//      WRITE = 1 — 10 каналов, LineOpen[k] на катод k;
//      WRITE = 0 — канал K0 (LineOpen[0]), канал общей шины остальных
//                  катодов (LineOpen[COMMON_LINE]) и при TOP_LIMIT_MODE
//                  канал TOP (LineOpen[TOP_PIN_OUT]).
//    Прежние входы In_n/SetData/SetZero/SetTop и выделенные сбросы
//    модели reset0_i/resetN_i убраны: в приборе их нет.
//
// 2. Исчез приём с маскированием выхода в X:
//        OutPos = (~(|_OutPos) | (|Pulses)) ? 10'bx : _OutPos;
//    Модель декатрона сама выдаёт нулевой позиционный код, пока разряд
//    не установился на главном катоде.
//
// 3. Формирователь импульсов перестроен: такт счёта делится на трети —
//    первый подкатод, второй подкатод, пауза на сваливание разряда.
//    Пауза внутри такта позволяет считать каждый такт (1 МГц), а не
//    через такт. Времязадающие элементы вынесены в DekatronPhaseGen и
//    моделируют RC-цепи реальной схемы.
//
// 4. Признака достоверности Valid (ИЛИ-10 по линиям чтения) больше нет.
//    Он показывал лишь то, что разряд стоит на каком-то главном катоде,
//    и ничего не говорил о том, закончена ли операция. Готовность
//    выводит DekatronCounter из известных длительностей: шаг, запись и
//    сброс по handshake укладываются в один такт Clk [TRS v0.24].
//
// 5. Формирователь подкатодных импульсов (DekatronPulseSender) и
//    генератор фаз перенесены в DekatronCounter: они одни на весь
//    счётчик и выдают общие шины GuideA/GuideB, уже с учётом
//    направления. Модуль только пропускает их на свои подкатоды двумя
//    ключами GUIDE_EN_J2 (по лампе J2 на подкатод) по сигналу En —
//    переносу в эту декаду (doc/tube_count_reduction.md §17, T5). Прежде
//    в каждой декаде стояло И-ИЛИ на 6 ламп.
//
//----------------------------------------------------------------------
// ТАКТИРОВАНИЕ
//
//   hsClk — временная база модели декатрона, всегда в 10 раз быстрее Clk
//           (1 МГц при Clk 100 кГц, TRS v0.24). Только для модели:
//           в железе декатрон отрабатывает длительности сам.
//
//   При `define DEKATRON_DELAY_MODEL вместо DekatronTubeV2 ставится
//   DekatronTubeDelay: та же модель на задержках #N, без hsClk вовсе
//   (только Icarus; run_tests.sh -d, synth_sim.sh -d).
//
//----------------------------------------------------------------------
// ПРАВИЛА ДЛЯ ВЫШЕСТОЯЩЕГО СЧЁТЧИКА
//
//   * Один шаг — один импульс GuideA и один GuideB за период Clk, в
//     порядке, задающем направление (их формирует счётчик). Пауза на
//     сваливание разряда заложена внутрь такта (третья треть), поэтому
//     шаги можно выдавать подряд каждый такт.
//   * En переключается по фронту Clk и держится весь такт. Снятие En в
//     середине такта оставит разряд на подкатоде.
//   * Линии чтения главных катодов отдельные и читаются всегда, но
//     показание Out_n достоверно только на фронте Clk, завершающем такт
//     операции. Пока разряд идёт по подкатодам, позиционный код нулевой.
//   * Закрытые линии LineOpen держатся не менее WRITE_MIN_HS тактов
//     hsClk, иначе разряд не перейдёт. Запись по handshake держится
//     один такт Clk [TRS v0.24], поэтому WRITE_MIN обязана укладываться
//     в такт (проверяет счётчик).
//   * Пока закрыта хоть одна линия, подкатоды молчат. Если линия
//     горящего катода закрыта, открытой должна остаться ровно одна.
//======================================================================

`default_nettype none

`ifndef SYNTH
// Ячейки декатронного модуля (TRS v0.40, sch/logic/DEKATRON_A110/README.md).
// В синтезе берутся из vtube_cells.lib: функции у них нет, ABC их не
// использует, они стоят только здесь и в DekatronCounter и считают лампы.
// Аналоговая часть (узел записи, шина ключей) — в SPICE.
//   WRCH_N16  — канал записи: ½ 6Н16Б в цепи катода (или общей шины катодов)
//   RDD_X7    — диод чтения: ½ 6Х7Б от сетки вентиля к катодной линии
//   GLIFT_N16 — повторитель анодной шины ключей подкатодов счётчика
module WRCH_N16 (
    input  wire A,
    output wire Y
);
    assign Y = A;
endmodule

module RDD_X7 (
    input  wire A,
    output wire Y
);
    assign Y = A;
endmodule

module GLIFT_N16 (
    input  wire A,
    output wire Y
);
    assign Y = A;
endmodule

// Модель ключа подкатодов. В синтезе ячейка берётся из vtube_cells.lib:
// у её выходов нет функции, ABC её не использует, она стоит только здесь.
module GUIDE_EN_J2 (
    input  wire EN,
    input  wire G,
    output wire Y
);
    assign Y = G & EN;
endmodule
`endif

(* keep_hierarchy = "yes" *)
module DekatronModule #(
    // Состав обвязки
    parameter bit          READ            = 1'b1,   // ставить BinToBcd
    parameter bit          WRITE           = 1'b1,   // 10 каналов записи (иначе только сброс)

    // Верхний предел счёта
    parameter bit          TOP_LIMIT_MODE  = 1'b1,   // выводить TopPin, свой канал сброса TOP
    parameter unsigned TOP_PIN_OUT     = 9,      // номер верхней позиции (свой канал сброса)

    // Начальное положение разряда после включения питания
    parameter logic [3:0]  INIT_DIGIT      = 4'd0,

    // Старшая цифра, до которой доходит разряд (TC-N1): катоды выше неё
    // не читаются и не пишутся. Сотни счётчика данных (предел 255) — 2
    parameter unsigned MAX_DIGIT       = 9,

    // Временные характеристики декатрона (такты hsClk)
    parameter unsigned GUIDE_STEP_HS   = 1,
    parameter unsigned FALL_STEP_HS    = 1,
    parameter unsigned GUIDE_MAX_HS    = 20,
    parameter unsigned WRITE_MIN_HS    = 5,      // запись и сброс по катоду

    // Нарезка такта счёта (такты hsClk); только для проверок ниже, сами
    // фазы формирует счётчик
    parameter unsigned HS_PER_CLK      = HSCLK_DIV,
    parameter unsigned PHASE1_HS       = 3,
    parameter unsigned PHASE2_HS       = 3,
    parameter unsigned PHASE_DELAY_HS  = 0,

    // Порядок фаз, дающий инкремент
    parameter bit          INC_BY_A_THEN_B = 1'b1
)(
`ifndef DEKATRON_DELAY_MODEL
/* verilator lint_off UNUSEDSIGNAL */
    input  wire       hsClk,     // временная база тактовой модели декатрона
/* verilator lint_on UNUSEDSIGNAL */
`endif

    // Счёт: общие шины подкатодов счётчика и разрешение этой декады
    input  wire       GuideA,
    input  wire       GuideB,
    input  wire       En,

    // Катодные линии записи W0…W9: 1 — канал открыт, 0 — закрыт.
    // При WRITE = 0 используются только линии 0, COMMON_LINE и TOP_PIN_OUT
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [9:0] LineOpen,
/* verilator lint_on UNUSEDSIGNAL */

    // Чтение
    output wire [3:0] Out_n,     // текущее число, 8-4-2-1 активным нулём (только при READ)

    // Признаки позиций для схемы переноса
    output wire       Zero,      // разряд на нулевом катоде
    output wire       Nine,      // разряд на девятом катоде
    output wire       TopPin     // разряд на катоде TOP_PIN_OUT
);

    //------------------------------------------------------------------
    // Внутренние связи
    //------------------------------------------------------------------
    wire [9:0] MainOneHotLine;  // катодные линии декатрона
    wire [9:0] MainOneHot;      // позиционный код за диодами чтения
    wire [9:0] CathodeOpen;     // линии, как их видит декатрон

    // Катоды выше MAX_DIGIT (TC-N1) остаются без диода и без канала записи
    localparam logic [9:0] DIG_MASK = 10'((1 << (MAX_DIGIT + 1)) - 1);
    // Линия общей шины платы сброса: первый катод, кроме K0 и TOP
    localparam int unsigned COMMON_LINE =
        (TOP_LIMIT_MODE && TOP_PIN_OUT == 1) ? 2 : 1;
    wire       GuideA_d;        // импульсы на подкатоды этой декады
    wire       GuideB_d;

    //------------------------------------------------------------------
    // Ключи подкатодов: по лампе J2 на подкатод
    //------------------------------------------------------------------
    GUIDE_EN_J2 guideEnA (
        .EN (En),
        .G  (GuideA),
        .Y  (GuideA_d)
    );

    GUIDE_EN_J2 guideEnB (
        .EN (En),
        .G  (GuideB),
        .Y  (GuideB_d)
    );

    //------------------------------------------------------------------
    // Катодные линии по перемычкам платы. Катоды выше MAX_DIGIT без
    // канала записи и без цепи возврата: гореть не могут, линия 0
    //------------------------------------------------------------------
    generate
        genvar k;
        for (k = 0; k < 10; k++) begin : g_line
            if (!DIG_MASK[k]) begin : g_none
                assign CathodeOpen[k] = 1'b0;
            end
            else if (WRITE) begin : g_full
                assign CathodeOpen[k] = LineOpen[k];
            end
            else if (k == 0) begin : g_k0
                assign CathodeOpen[k] = LineOpen[0];
            end
            else if (TOP_LIMIT_MODE && k == int'(TOP_PIN_OUT)) begin : g_top
                assign CathodeOpen[k] = LineOpen[TOP_PIN_OUT];
            end
            else begin : g_common
                assign CathodeOpen[k] = LineOpen[COMMON_LINE];
            end
        end
    endgenerate

    //------------------------------------------------------------------
    // Декатрон
    //------------------------------------------------------------------
    // `DEKATRON_DELAY_MODEL: модель на задержках #N без hsClk
    // (DekatronTubeDelay.sv, синтез и нетлист), длительности в нс из
    // макросов DEKATRON_*_NS [TRS v0.25]. Иначе — тактовая модель.
`ifdef DEKATRON_DELAY_MODEL
    DekatronTubeDelay #(
        .GUIDE_STEP_NS    (`DEKATRON_GUIDE_STEP_NS),
        .FALL_STEP_NS     (`DEKATRON_FALL_STEP_NS),
        .GUIDE_MAX_NS     (`DEKATRON_GUIDE_MAX_NS),
        .WRITE_MIN_NS     (`DEKATRON_WRITE_MIN_NS),
`else
    DekatronTubeV2 #(
        .GUIDE_STEP_HS    (GUIDE_STEP_HS),
        .FALL_STEP_HS     (FALL_STEP_HS),
        .GUIDE_MAX_HS     (GUIDE_MAX_HS),
        .WRITE_MIN_HS     (WRITE_MIN_HS),
`endif
        .LINES            (DIG_MASK),
        .INIT_DIGIT       (INIT_DIGIT),
        .INC_BY_A_THEN_B  (INC_BY_A_THEN_B),
        .EN_SIM_PRESET    (1'b0),
        .EN_DEBUG_OUTPUTS (1'b0)
    ) dekatron (
`ifndef DEKATRON_DELAY_MODEL
        .hsClk                 (hsClk),
`endif
        .guide_a_i             (GuideA_d),
        .guide_b_i             (GuideB_d),
        .line_open_i           (CathodeOpen),
        .sim_preset_en_i       (1'b0),
        .sim_preset_cathodes_i (30'b0),
        .main_onehot_o         (MainOneHotLine),
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
    // Диоды чтения (RDD_X7, ½ 6Х7Б на линию): все десять линий при READ,
    // иначе только линии признаков — K0, K9 и катод TOP_PIN_OUT
    //------------------------------------------------------------------
    localparam logic [9:0] READ_LINES = DIG_MASK & (
        READ ? 10'h3FF :
        (10'b10_0000_0001 | (TOP_LIMIT_MODE ? (10'b1 << TOP_PIN_OUT) : 10'b0)));

    generate
        for (k = 0; k < 10; k++) begin : g_rdd
            if (READ_LINES[k]) begin : g_on
                RDD_X7 rdd (
                    .A (MainOneHotLine[k]),
                    .Y (MainOneHot[k])
                );
            end
            else begin : g_off
                // линия не читается; выше MAX_DIGIT её нет вовсе
                assign MainOneHot[k] = DIG_MASK[k] ? MainOneHotLine[k] : 1'b0;
            end
        end
    endgenerate

    //------------------------------------------------------------------
    // Каналы записи (WRCH_N16, ½ 6Н16Б), по перемычкам платы:
    // полная запись — 10; сброс в 0 и TOP — K0, K_TOP, общая шина
    // остальных; сброс в 0 — K0 и общая шина K1..K9. Вход — уровень линии
    // (1 — открыт, спад закрывает лампу через Cс). Выход — аналоговый
    // узел записи, в нетлисте не подключён
    //------------------------------------------------------------------
    generate
        if (WRITE) begin : g_wrch_full
            for (k = 0; k <= int'(MAX_DIGIT); k++) begin : g_ch
                /* verilator lint_off PINCONNECTEMPTY */
                (* keep *) WRCH_N16 wrch (.A (LineOpen[k]), .Y ());
                /* verilator lint_on PINCONNECTEMPTY */
            end
        end
        else begin : g_wrch_reset
            /* verilator lint_off PINCONNECTEMPTY */
            (* keep *) WRCH_N16 wrch_k0     (.A (LineOpen[0]),           .Y ());
            (* keep *) WRCH_N16 wrch_common (.A (LineOpen[COMMON_LINE]), .Y ());
            if (TOP_LIMIT_MODE) begin : g_k_top
                (* keep *) WRCH_N16 wrch_top (.A (LineOpen[TOP_PIN_OUT]), .Y ());
            end
            /* verilator lint_on PINCONNECTEMPTY */
        end
    endgenerate

    //------------------------------------------------------------------
    // Схема чтения — только при READ
    //------------------------------------------------------------------
    generate
        if (READ) begin : g_read
            BinToBcdN binToBcd (
                .In    (MainOneHot),
                .Out_n (Out_n)
            );
        end
        else begin : g_no_read
            assign Out_n = 4'b1111;   // как показание 0
        end
    endgenerate

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
`ifdef DEKATRON_DELAY_MODEL
        // Модель на задержках: те же условия в нс, на такт CLK_PERIOD_NS
        if (`DEKATRON_PHASE1_NS < `DEKATRON_GUIDE_STEP_NS ||
            `DEKATRON_PHASE2_NS < `DEKATRON_GUIDE_STEP_NS)
            $error("DekatronModule: фаза короче DEKATRON_GUIDE_STEP_NS: разряд не успеет уйти на подкатод");
        if (`DEKATRON_PHASE_DELAY_NS + `DEKATRON_PHASE1_NS + `DEKATRON_PHASE2_NS +
            `DEKATRON_FALL_STEP_NS >= CLK_PERIOD_NS)
            $error("DekatronModule: фазы и сваливание (%0d нс) не укладываются в такт Clk (%0d нс)",
                   `DEKATRON_PHASE_DELAY_NS + `DEKATRON_PHASE1_NS + `DEKATRON_PHASE2_NS +
                   `DEKATRON_FALL_STEP_NS, CLK_PERIOD_NS);
`else
        // Фазы обязаны вмещать переход разряда на подкатод
        if (PHASE1_HS < GUIDE_STEP_HS)
            $error("DekatronModule: PHASE1_HS (%0d) < GUIDE_STEP_HS (%0d): разряд не успеет уйти на подкатод",
                   PHASE1_HS, GUIDE_STEP_HS);
        if (PHASE2_HS < GUIDE_STEP_HS)
            $error("DekatronModule: PHASE2_HS (%0d) < GUIDE_STEP_HS (%0d): разряд не успеет уйти на второй подкатод",
                   PHASE2_HS, GUIDE_STEP_HS);

        // Третья треть обязана вмещать сваливание на главный катод С
        // ЗАПАСОМ хотя бы в один такт hsClk. Признака Valid нет: счётчик
        // считает шаг законченным к следующему фронту Clk и защёлкивает
        // по нему признаки переноса и нуля. При окне ровно FALL_STEP_HS
        // разряд падает на главный катод на том же фронте (гонка), и
        // защёлкивается состояние «на подкатоде». Так было при 3/4/3.
        if ((HS_PER_CLK - PHASE_DELAY_HS - PHASE1_HS - PHASE2_HS) <= FALL_STEP_HS)
            $error("DekatronModule: окно сваливания (%0d) <= FALL_STEP_HS (%0d): шаг не укладывается в такт Clk",
                   HS_PER_CLK - PHASE_DELAY_HS - PHASE1_HS - PHASE2_HS, FALL_STEP_HS);

        if ((PHASE_DELAY_HS + PHASE1_HS + PHASE2_HS) >= HS_PER_CLK)
            $error("DekatronModule: фазы занимают весь такт, окна сваливания не остаётся");
`endif

        if (MAX_DIGIT > 9 || (TOP_LIMIT_MODE && TOP_PIN_OUT > MAX_DIGIT))
            $error("DekatronModule: MAX_DIGIT (%0d) must be 0..9 and cover TOP_PIN_OUT (%0d)",
                   MAX_DIGIT, TOP_PIN_OUT);
        if (TOP_PIN_OUT > 9)
            $error("DekatronModule: TOP_PIN_OUT (%0d) must be in range 0..9",
                   TOP_PIN_OUT);
        if (TOP_LIMIT_MODE && !WRITE && (TOP_PIN_OUT == 0))
            $error("DekatronModule: TOP_PIN_OUT = 0 on a reset board is K0 itself");
        if (!WRITE && MAX_DIGIT < 2)
            $error("DekatronModule: a reset board needs a common line (MAX_DIGIT >= 2)");
    end
`endif

endmodule

`default_nettype wire
