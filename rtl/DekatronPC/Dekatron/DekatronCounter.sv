//======================================================================
// DekatronCounter — многоразрядный реверсивный декатронный счётчик
//----------------------------------------------------------------------
// Собран из DekatronModule. Предоставляет вышестоящим блокам
// классический Valid/Ready интерфейс.
//
// Это ПЕРВЫЙ уровень иерархии, где handshake вообще имеет смысл: сам
// декатрон физически не может выдавать ready/busy, он только отрабатывает
// внешние воздействия заданной длительности. Вся дисциплина операций
// (выдержка длительностей, удержание уровней весь такт, ожидание
// установления разряда) сосредоточена здесь.
//
//----------------------------------------------------------------------
// ПРОТОКОЛ [TRS v0.24]
//
//   accept = valid & ready — операция принимается по фронту clk.
//   ready НЕ зависит от valid.
//
//   Такт счёта по умолчанию 100 кГц (10 мкс); hs_clk, как всегда, в
//   HS_PER_CLK = 10 раз быстрее, 1 мкс. За такт декатрон успевает и шагнуть, и записаться, поэтому
//   ЛЮБАЯ операция — шаг, запись, сброс в нуль, переход через край —
//   выполняется в такте accept и завершена к следующему фронту clk.
//   Автомата состояний и реле времени окна записи больше нет: счётчик
//   почти комбинационный, ready снимается только физическими линиями
//   сброса. Пропускная способность — одна операция за такт.
//
//   Шаг подаётся уровнем на весь такт accept; DekatronPulseSender
//   нарезает его на два подкатодных импульса и паузу на сваливание.
//   Запись (set, set_zero, переход через край) тоже подаётся уровнем:
//   линия записи на декады — это сам accept, от прихода valid до
//   фронта. Декатрону её хватает, если WRITE_MIN_HS и RESET_MIN_HS
//   укладываются в такт за вычетом пути команды (проверка ниже).
//
//   Показания катодов (out_n, zero, at_top) идут другими линиями и
//   читаются всегда, но достоверны только на фронте clk, завершающем
//   такт операции: внутри такта шага разряд идёт по подкатодам, внутри
//   такта записи — переходит на новый катод.
//
//   Операнды не защёлкиваются: признаки dec, set, set_zero и число in_n
//   держатся мастером весь такт accept (valid не снимается до
//   рукопожатия, а рукопожатие и есть такт операции).
//
//   Физические линии сброса soft_rst/hard_rst идут прямо на катоды
//   декад, их длительность держит внешнее реле времени. Пока линия
//   поднята, ready снят; на следующем фронте после её снятия счётчик
//   снова готов.
//
//----------------------------------------------------------------------
// ЧТО ИЗМЕНИЛОСЬ ОТНОСИТЕЛЬНО ПРЕЖНЕЙ ВЕРСИИ
//
// 1. Импульсный Request заменён на Valid/Ready (TRS v0.10).
//
// 2. Шаг формируется комбинационно из accept и подаётся уровнем на
//    весь такт; DekatronPulseSender сам нарезает такт на фазы.
//
// 3. Сбросы — физические линии счётчика, а не асинхронные входы
//    декатрона. Разводку по декадам выполняет счётчик:
//
//      soft_rst -> линия set0 всех декад                  -> 0
//      hard_rst -> линия set9 старших HARD_RST_D_CNT декад,
//                  линия set0 остальных                   -> 99900
//
// 4. Признака out_valid нет: готовность выводится из длительностей.
//
// 5. Генератор фаз и формирователь подкатодных импульсов — один на
//    счётчик; декада пропускает общие шины guide_a/guide_b двумя
//    ключами GUIDE_EN_J2 по разрешению en_chain[d] (doc/
//    tube_count_reduction.md §17, T5).
//
// 6. [TRS v0.24] Такт 100 кГц: запись и сброс по handshake укладываются
//    в один такт. Ушли автомат ST_IDLE/SET/ZERO/TOP/RST (3 триггера),
//    упрощённый вариант с одним busy_q и реле времени окна записи
//    (Impulse writeStart + OneShot writeTimer). Остались только
//    признаки «до шага» nines_q/zeroes_q и, в режиме верхнего предела,
//    zero_q/at_top_q (doc/dekatron_counter_single_cycle.md).
//
//----------------------------------------------------------------------
// ЦЕПОЧКА ПЕРЕНОСА
//
// Перенос «бесплатный»: разряд сам уходит в соседнюю декаду. Шаг
// пробрасывается дальше, если младшая декада стояла на 9 (инкремент)
// или на 0 (декремент) ДО текущего шага. Значения nines/zeroes
// защёлкиваются по фронту clk, поэтому весь такт стабильны и вся
// цепочка распространяется в пределах одного такта clk.
//======================================================================

`default_nettype none

`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
// Модель ячейки LATCH_J2N16 (sch/logic/DLATCH2_J2N16) для симуляции RTL;
// в синтезе — ячейка liberty, в нетлисте — sch/logic/vtube_cells.v
module LATCH_J2N16 (
    input  wire C,
    input  wire D,
    output reg  Q,
    output wire QN
);
    assign QN = ~Q;
    always @*
        if (C) Q = D;
endmodule
`endif
`endif

// Задержка начала фаз от фронта Clk, такты hsClk (REQ-PULSE-009): не
// короче худшего пути команды шага. В RTL вентили без задержки — 0;
// нетлист с задержками ламп задаёт её через synth_sim.sh -t
`ifndef DEKATRON_PHASE_DELAY_HS
`define DEKATRON_PHASE_DELAY_HS 0
`endif

// Длительность фаз подкатодов, такты hsClk. Декатрону всё равно, как
// медленно его переключать (не короче GUIDE_STEP_HS), а ламповый
// формирователь DekatronPulseSender не пропускает импульс короче своего
// времени переключения (NAND2_J2 345–545 нс). В RTL — 3 + 3;
// ламповую машину собирают с фазами под её такт: synth_sim.sh -w,
// vtube_sta.sh подбирает наименьшие (doc/vtube_sta.md §6)
`ifndef DEKATRON_PHASE1_HS
`define DEKATRON_PHASE1_HS 3
`endif
`ifndef DEKATRON_PHASE2_HS
`define DEKATRON_PHASE2_HS 3
`endif

module DekatronCounter #(
    parameter unsigned D_NUM          = 3,
    parameter unsigned WIDTH          = D_NUM * DEKATRON_WIDTH,

    // Состав обвязки декад
    parameter bit          READ           = 1'b1,
    parameter bit          WRITE          = 1'b1,

    // Режим верхнего предела: при достижении TOP_VALUE инкремент даёт 0,
    // а декремент из нуля даёт TOP_VALUE
    parameter bit          TOP_LIMIT_MODE = 1'b0,
    // По умолчанию 5 во всех декадах; ширина следует за D_NUM
    parameter [WIDTH-1:0]  TOP_VALUE      = {D_NUM{4'd5}},

    // Сколько старших декад операция set_hard устанавливает в 9.
    // 0 — операция set_hard не поддерживается.
    parameter unsigned HARD_RST_D_CNT = 0,

    // Нарезка такта счёта: тактов hs_clk на такт clk (hs_clk всегда в 10
    // раз быстрее clk; период clk — параметр сборки DEKATRON_CLK_NS,
    // rtl/parameters.sv, по умолчанию 10 мкс)
    parameter unsigned HS_PER_CLK     = HSCLK_DIV,
    parameter unsigned PHASE1_HS      = `DEKATRON_PHASE1_HS,
    parameter unsigned PHASE2_HS      = `DEKATRON_PHASE2_HS,
    parameter unsigned PHASE_DELAY_HS = `DEKATRON_PHASE_DELAY_HS,

    // Временные характеристики декатрона (такты hs_clk, 1 мкс при
    // 100 кГц), оценки до измерений (OPEN-013). Шаг на подкатод и
    // сваливание (200 и 300 нс) округлены вверх до такта hs_clk. Запись
    // и сброс по катоду обязаны уложиться в такт accept: половина такта
    parameter unsigned GUIDE_STEP_HS  = 1,
    parameter unsigned FALL_STEP_HS   = 1,
    parameter unsigned WRITE_MIN_HS   = HS_PER_CLK / 2,
    parameter unsigned RESET_MIN_HS   = HS_PER_CLK / 2

)(
    input  wire             rst_n,      // сброс логики фаз; разряд НЕ двигает
    input  wire             clk,        // такт счёта
`ifndef DEKATRON_DELAY_MODEL
    input  wire             hs_clk,     // временная база тактовой модели декатронов
`endif

    // Физические линии сброса. Идут прямо на катодные линии декад в
    // обход handshake: разводку по декадам делает счётчик.
    //   soft_rst — все декады в нуль
    //   hard_rst — старшие HARD_RST_D_CNT декад в девятку, остальные в нуль
    // Длительность держит внешнее реле времени: не менее RESET_MIN_HS
    // тактов hs_clk, иначе разряд не успеет перейти на нужный катод.
    input  wire             soft_rst,
    input  wire             hard_rst,

    // Valid/Ready
    input  wire             valid,
    output wire             ready,

    // Признаки операции, квалифицируются valid
    input  wire             dec,        // 1 — декремент, 0 — инкремент
    input  wire             set,        // записать in_n
    input  wire             set_zero,   // сбросить в нуль
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [WIDTH-1:0] in_n,       // записываемое число, тетрады активным нулём (TC-O3)
/* verilator lint_on UNUSEDSIGNAL */

    // Результат: катоды читаются всегда, достоверны на фронте clk
    output wire [WIDTH-1:0] out_n,      // показание, тетрады активным нулём (BinToBcdN, TC-O3)
    output wire             zero,       // счётчик равен нулю
    output wire             at_top      // счётчик равен TOP_VALUE
);

    localparam unsigned DW = DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Показания декад
    //------------------------------------------------------------------
    logic [D_NUM-1:0] dek_zero;      // комбинационно с декад
    logic [D_NUM-1:0] dek_nine;
    logic [D_NUM-1:0] dek_top;

    // Выходные признаки берутся прямо с катодов, как и out_n. В режиме без
    // верхнего предела at_top — «все декады на девятке»; он нужен только
    // счётчику вложенности для ошибки переполнения.
    assign zero   = &dek_zero;
    assign at_top = TOP_LIMIT_MODE ? &dek_top : &dek_nine;

    //------------------------------------------------------------------
    // Признаки ДО текущей операции, защёлкнутые по фронту clk
    //
    // Нужны там, где решение принимается внутри такта операции: разряд
    // уходит с главного катода уже в первой фазе, а шаг и запись обязаны
    // держаться на декаде весь такт. Защёлкивается только то, что
    // действительно читается:
    //   nines_q/zeroes_q — цепочка переноса; старшая декада переноса
    //                      никуда не отдаёт, поэтому D_NUM-1 разрядов;
    //   zero_q/at_top_q  — автопереходы через край, только в режиме
    //                      верхнего предела.
    //
    // Сброса у них нет: защёлкиваются с катодов на каждом фронте clk, а
    // любая операция, включая запись, завершается к следующему фронту,
    // поэтому на фронте начала операции они всегда достоверны.
    //------------------------------------------------------------------
    localparam unsigned CW = (D_NUM > 1) ? D_NUM - 1 : 1;

`ifndef DEKATRON_DELAY_MODEL
    logic [CW-1:0] zeroes_q;
    logic [CW-1:0] nines_q;

    always_ff @(posedge clk) begin
        zeroes_q <= dek_zero[CW-1:0];
        nines_q  <= dek_nine[CW-1:0];
    end
`endif

    //------------------------------------------------------------------
    // Готовность и приём операции
    //
    // Пока поднята линия сброса, подкатодные импульсы и запись на декады
    // недопустимы, поэтому ready снят. Больше ничего ready не снимает:
    // любая операция укладывается в свой такт.
    //------------------------------------------------------------------
    wire rst_active = soft_rst | hard_rst;

    assign ready = ~rst_active;

    wire accept = valid & ready;

    //------------------------------------------------------------------
    // Автопереходы через край в режиме верхнего предела
    //------------------------------------------------------------------
    wire set_top_int;
    wire set_zero_int;

    generate
        if (TOP_LIMIT_MODE) begin : g_top_limit
            logic zero_q;
            logic at_top_q;

            always_ff @(posedge clk) begin
                zero_q   <= &dek_zero;
                at_top_q <= &dek_top;
            end

            // Только защёлкнутые признаки: живые с катодов изменятся
            // внутри такта операции и оборвут запись (254+1 -> 0)
            assign set_top_int  = zero_q   &  dec;   // 0 - 1   -> TOP_VALUE
            assign set_zero_int = at_top_q & ~dec;   // TOP + 1 -> 0
        end
        else begin : g_no_top_limit
            assign set_top_int  = 1'b0;
            assign set_zero_int = 1'b0;
        end
    endgenerate

    //------------------------------------------------------------------
    // Линии шага и записи: всё комбинационно из accept
    //
    // Явные операции приоритетнее автопереходов через край. Операция
    // set при WRITE = 0 пустая: схемы записи нет, шаг не выдаётся
    // (assertion ниже сообщает о ней как об ошибке).
    //------------------------------------------------------------------
    wire set_any = set | set_zero | set_top_int | set_zero_int;

    wire step_f  = accept & ~set_any & ~dec;
    wire step_r  = accept & ~set_any &  dec;

    wire wr_set  = accept &  set & WRITE;
    wire wr_zero = accept & ~set & (set_zero | set_zero_int);
    wire wr_top  = accept & ~set & ~set_zero & set_top_int;

    // Сброс: в старшие декады девятка, если сброс аппаратный
    wire rst_to_nine = hard_rst;
    wire rst_to_zero = soft_rst & ~hard_rst;

    // Подъём подкатодов на время записи и сброса (sch/logic/DEKATRON_A110,
    // §9.3): повторитель анодной шины ключей, один на счётчик (GLIFT_N16).
    // Выход — аналоговая шина ключей, в нетлисте не подключён
    wire guide_lift = wr_set | wr_zero | wr_top | soft_rst | hard_rst;
    /* verilator lint_off PINCONNECTEMPTY */
    (* keep *) GLIFT_N16 guideLift (.A (guide_lift), .Y ());
    /* verilator lint_on PINCONNECTEMPTY */

    // hs_clk — временная база только тактовой модели (FPGA, симуляция
    // без задержек). В модели на задержках (`DEKATRON_DELAY_MODEL: синтез
    // и нетлист ламповой машины) порта hs_clk нет вовсе: RC-цепи и
    // декатрон отсчитывают время сами, в нс [TRS v0.25].

    //------------------------------------------------------------------
    // Общий генератор фаз на весь счётчик
    //------------------------------------------------------------------
    wire phase1;
    wire phase2;
    wire cmd_win;   // от фронта Clk до начала фаз

    DekatronPhaseGen #(
        .PHASE1_HS      (PHASE1_HS),
        .PHASE2_HS      (PHASE2_HS),
        .PHASE_DELAY_HS (PHASE_DELAY_HS)
    ) phaseGen (
`ifndef DEKATRON_DELAY_MODEL
        .hsClk  (hs_clk),
`endif
        .Clk    (clk),
        .Rst_n  (rst_n),
        .Phase1 (phase1),
        .Phase2 (phase2),
        .CmdWin (cmd_win)
    );

    //------------------------------------------------------------------
    // Общий формирователь подкатодных импульсов (п. 5 заголовка)
    //
    // Шины guide_a/guide_b несут импульсы шага всего счётчика, уже в
    // порядке, заданном направлением. Какие декады шагнут, решает
    // en_chain: декада пропускает шины на свои подкатоды ключом
    // GUIDE_EN_J2 (по лампе на подкатод) внутри DekatronModule.
    //------------------------------------------------------------------
    wire guide_a;
    wire guide_b;

    DekatronPulseSender #(
        .EXT_PHASES (1'b1),
        .PHASE1_HS  (PHASE1_HS),
        .PHASE2_HS  (PHASE2_HS)
    ) pulseSender (
`ifndef DEKATRON_DELAY_MODEL
        .hsClk    (hs_clk),
`endif
        .Clk      (clk),
        .Rst_n    (rst_n),
        .StepF    (step_f),
        .StepR    (step_r),
        .Phase1_i (phase1),
        .Phase2_i (phase2),
        .GuideA   (guide_a),
        .GuideB   (guide_b)
    );

    //------------------------------------------------------------------
    // Декады
    //------------------------------------------------------------------
    //------------------------------------------------------------------
    // Цепочка переноса
    //
    // Перенос идёт строго от младшей декады к старшей и распространяется
    // в пределах одного такта. Шаг проходит дальше, если младшая декада
    // стояла на 9 (инкремент) или на 0 (декремент) ДО текущего шага.
    // Сам шаг и направление уже несут шины guide_a/guide_b, поэтому
    // цепочка одна: en_chain[d] — разрешение декаде d, младшая разрешена
    // всегда. Вне такта шага шины пусты и en_chain ни на что не влияет.
    //
    // Рипл вынесен в локальные переменные, а вектор en_chain только
    // записывается и нигде не читается. Если писать его поразрядно как
    //
    //     assign en_chain[d] = en_chain[d-1] & nines_q[d-1];
    //
    // то Verilator анализирует зависимости с точностью до целого сигнала
    // и видит зависимость вектора от самого себя: UNOPTFLAT на en_chain.
    // Физически петли нет, но предупреждение приходится либо подавлять,
    // либо устранять структурно. Здесь выбрано второе: подавление скрыло
    // бы и настоящие петли, если они появятся.
    //------------------------------------------------------------------
    logic [D_NUM-1:0] en_chain;

`ifdef DEKATRON_DELAY_MODEL
    //------------------------------------------------------------------
    // Ламповая машина: защёлка разрешения на декаду (doc/
    // tube_count_1000.md §3). Цепочка считается с живых катодов и dec;
    // защёлка прозрачна в окне команды cmd_win (от фронта Clk до начала
    // фаз, задержка фаз REQ-PULSE-009), когда разряды стоят на главных
    // катодах прошлой операции, и закрыта на обе фазы и сваливание, пока
    // младшие декады уходят с 0/9. Так же, как прежние триггеры nines_q/
    // zeroes_q, она держит состояние «до шага», но одна защёлка (3,5
    // лампы) на декаду вместо двух триггеров (2 × 7). Декады в окне
    // команды может двигать только запись, а записи разрешения не нужны.
    // dec держится мастером весь такт (valid до рукопожатия) и успевает
    // к концу окна, как и сама команда шага.
    //------------------------------------------------------------------
    logic [D_NUM-1:0] carry_live;

    always_comb begin
        logic carry;

        carry = 1'b1;
        carry_live[0] = carry;

        for (int i = 1; i < int'(D_NUM); i++) begin
            carry = carry & (dec ? dek_zero[i-1] : dek_nine[i-1]);
            carry_live[i] = carry;
        end
    end

    assign en_chain[0] = 1'b1;

    generate
        genvar e;
        for (e = 1; e < int'(D_NUM); e++) begin : enLatch
            LATCH_J2N16 enLatch (
                .C  (cmd_win),
                .D  (carry_live[e]),
                .Q  (en_chain[e]),
                .QN ()
            );
        end
    endgenerate
`else

    always_comb begin
        logic carry;

        carry = 1'b1;
        en_chain[0] = carry;

        for (int i = 1; i < int'(D_NUM); i++) begin
            carry = carry & (dec ? zeroes_q[i-1] : nines_q[i-1]);
            en_chain[i] = carry;
        end
    end
`endif

    generate
        genvar d;
        for (d = 0; d < int'(D_NUM); d++) begin : dek

            // Декада, которую операция set_hard устанавливает в 9
            localparam bit IS_HARD_DEC =
                (HARD_RST_D_CNT > 0) && (d + int'(HARD_RST_D_CNT) >= int'(D_NUM));

            // Позиция линии resetN этой декады:
            //   в режиме верхнего предела — цифра TOP_VALUE,
            //   для предустановки — девятка,
            //   иначе линия не ставится вовсе.
            localparam unsigned RESET_N_POS_D =
                TOP_LIMIT_MODE ? int'(TOP_VALUE[(d+1)*DW-1 -: DW]) :
                (IS_HARD_DEC   ? 9 : 0);

            localparam bit EN_RESET_N_D = TOP_LIMIT_MODE || IS_HARD_DEC;
            localparam bit IS_TOP_DEC   = TOP_LIMIT_MODE && (d == int'(D_NUM) - 1);


            //----------------------------------------------------------
            // Линии установки для этой декады
            //----------------------------------------------------------
            // Сюда сходятся оба источника: операции по handshake и
            // физические линии сброса
            wire dek_set_zero = wr_zero | rst_to_zero |
                                (rst_to_nine & ~IS_HARD_DEC);
            wire dek_set_top  = wr_top  | (rst_to_nine & IS_HARD_DEC);

            DekatronModule #(
                .READ            (READ),
                .WRITE           (WRITE),
                .TOP_LIMIT_MODE  (EN_RESET_N_D),
                .TOP_PIN_OUT     (RESET_N_POS_D),
                .INIT_DIGIT      (4'd0),
                // Верхняя декада с пределом не уходит выше цифры предела (TC-N1)
                .MAX_DIGIT       (IS_TOP_DEC ? int'(TOP_VALUE[(d+1)*DW-1 -: DW]) : 9),
                .GUIDE_STEP_HS   (GUIDE_STEP_HS),
                .FALL_STEP_HS    (FALL_STEP_HS),
                .WRITE_MIN_HS    (WRITE_MIN_HS),
                .RESET_MIN_HS    (RESET_MIN_HS),
                .HS_PER_CLK      (HS_PER_CLK),
                .PHASE1_HS       (PHASE1_HS),
                .PHASE2_HS       (PHASE2_HS),
                .PHASE_DELAY_HS  (PHASE_DELAY_HS)
            ) dModule (
`ifndef DEKATRON_DELAY_MODEL
                .hsClk    (hs_clk),
`endif
                .GuideA   (guide_a),
                .GuideB   (guide_b),
                .En       (en_chain[d]),
                .In_n     (in_n[(d+1)*DW-1 -: DW]),
                .SetData  (wr_set),
                .SetZero  (dek_set_zero),
                .SetTop   (dek_set_top),
                .Out_n    (out_n[(d+1)*DW-1 -: DW]),
                .Zero     (dek_zero[d]),
                .Nine     (dek_nine[d]),
                .TopPin   (dek_top[d])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // Проверки
    //------------------------------------------------------------------
`ifndef SYNTH
    initial begin
        if (TOP_LIMIT_MODE && (HARD_RST_D_CNT > 0))
            $error("DekatronCounter: TOP_LIMIT_MODE и HARD_RST_D_CNT используют одну и ту же линию resetN декатрона и несовместимы");
        if (HARD_RST_D_CNT > D_NUM)
            $error("DekatronCounter: HARD_RST_D_CNT (%0d) больше числа декад (%0d)",
                   HARD_RST_D_CNT, D_NUM);
        // Запись по handshake держится от прихода команды (не раньше
        // задержки фаз, REQ-PULSE-009) до фронта, завершающего такт, и
        // показание должно установиться до этого фронта: хотя бы один
        // такт hs_clk запаса. В модели на задержках — то же в нс
`ifdef DEKATRON_DELAY_MODEL
        if (`DEKATRON_PHASE_DELAY_NS + `DEKATRON_WRITE_MIN_NS >= CLK_PERIOD_NS ||
            `DEKATRON_PHASE_DELAY_NS + `DEKATRON_RESET_MIN_NS >= CLK_PERIOD_NS)
            $error("DekatronCounter: запись или сброс по катоду после задержки команды не укладывается в такт Clk (%0d нс)",
                   CLK_PERIOD_NS);
`else
        if (PHASE_DELAY_HS + WRITE_MIN_HS >= HS_PER_CLK)
            $error("DekatronCounter: запись (%0d hs) после задержки команды (%0d hs) не укладывается в такт (%0d hs)",
                   WRITE_MIN_HS, PHASE_DELAY_HS, HS_PER_CLK);
        if (PHASE_DELAY_HS + RESET_MIN_HS >= HS_PER_CLK)
            $error("DekatronCounter: сброс по катоду (%0d hs) после задержки команды (%0d hs) не укладывается в такт (%0d hs)",
                   RESET_MIN_HS, PHASE_DELAY_HS, HS_PER_CLK);
`endif
        if (WIDTH != D_NUM * DEKATRON_WIDTH)
            $error("DekatronCounter: WIDTH (%0d) не соответствует D_NUM*DEKATRON_WIDTH (%0d)",
                   WIDTH, D_NUM * DEKATRON_WIDTH);
        if (!WRITE)
            $display("DekatronCounter: WRITE=0, операция set недоступна (схема записи не ставится)");
    end


`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && valid) begin
            if ((set + set_zero) > 1)
                $error("DekatronCounter: одновременно запрошено несколько операций установки");
            if (set && !WRITE)
                $error("DekatronCounter: операция set при WRITE=0");
        end
        if (rst_n && soft_rst && hard_rst)
            $error("DekatronCounter: soft_rst и hard_rst подняты одновременно");
        // valid не должен сниматься до handshake
        if (rst_n && $past(valid) && !$past(ready) && !valid)
            $error("DekatronCounter: valid снят до handshake");
    end
`endif
`endif

endmodule

`default_nettype wire
