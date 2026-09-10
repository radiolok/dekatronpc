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
// ПРОТОКОЛ
//
//   accept = valid & ready — операция принимается по фронту clk.
//   ready НЕ зависит от valid.
//
//   Быстрый путь (инкремент/декремент): ready не снимается вовсе,
//   пропускная способность — одна операция за такт clk.
//
//   Медленный путь (запись, сбросы): ready снимается на время окна
//   записи, около WRITE_MIN_HS тактов hs_clk (по умолчанию 10 тактов clk).
//
//   Операнды защёлкиваются по accept, поэтому мастер не обязан удерживать
//   in и признаки операции на всё время выполнения.
//
//----------------------------------------------------------------------
// ЧТО ИЗМЕНИЛОСЬ ОТНОСИТЕЛЬНО ПРЕЖНЕЙ ВЕРСИИ
//
// 1. Импульсный Request заменён на Valid/Ready. Прежде ready зависел от
//    ~request, и мастер был обязан сначала снять запрос и только потом
//    ждать готовности — это был квазидвухфазный протокол, а не ST.
//
// 2. Состояния INC и DEC исчезли. Прежде они существовали только чтобы
//    сформировать одиночный импульс и стоили лишнего такта. Теперь шаг
//    формируется комбинационно из accept, инкремент занимает один такт.
//
// 3. Шаг подаётся УРОВНЕМ на весь такт, а не импульсом. Новый
//    DekatronPulseSender сам нарезает такт на трети: два подкатодных
//    импульса и пауза на сваливание разряда. Импульсные прослойки
//    Impulse на пути шага больше не нужны.
//
// 4. Сбросы стали физическими линиями счётчика, а не асинхронными
//    входами декатрона. У декатрона цифровых сбросов нет вовсе:
//    установка позиции — это импульс по катоду. Разводку выполняет
//    счётчик, потому что только он знает, куда сбрасываться:
//
//      soft_rst -> линия set0 всех декад                  -> 0
//      hard_rst -> линия set9 старших HARD_RST_D_CNT декад,
//                  линия set0 остальных                   -> 99900
//
//    Длительность обеспечивает внешнее реле времени: линия удерживается
//    не менее RESET_MIN_HS тактов hs_clk. Растяжки внутри счётчика нет —
//    это была бы лишняя логика поверх уже существующей физической цепи.
//
// 5. Появился out_valid. Пока разряд идёт по подкатодам, ни один главный
//    катод не светится и позиционный код нулевой, что неотличимо от
//    настоящего нуля. Прежде эту неопределённость маскировали выдачей X.
//
// 6. Генератор фаз один на весь счётчик, а не в каждом модуле: фазы
//    одинаковы для всех декад, а шагает та, которой цепочка переноса
//    разрешила. Для шестидекадного счётчика это пять сэкономленных
//    времязадающих цепей.
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

module DekatronCounter #(
    parameter unsigned D_NUM          = 4'd3,
    parameter unsigned WIDTH          = D_NUM * DEKATRON_WIDTH,

    // Состав обвязки декад
    parameter bit          READ           = 1'b1,
    parameter bit          WRITE          = 1'b1,

    // Режим верхнего предела: при достижении TOP_VALUE инкремент даёт 0,
    // а декремент из нуля даёт TOP_VALUE
    parameter bit          TOP_LIMIT_MODE = 1'b0,
    /* verilator lint_off WIDTHEXPAND */
    parameter [WIDTH-1:0]  TOP_VALUE      = {4'd5, 4'd5, 4'd5},
    /* verilator lint_on WIDTHEXPAND */

    // Сколько старших декад операция set_hard устанавливает в 9.
    // 0 — операция set_hard не поддерживается.
    parameter unsigned HARD_RST_D_CNT = 0,

    // Временные характеристики декатрона (такты hs_clk)
    parameter unsigned GUIDE_STEP_HS  = 2,
    parameter unsigned FALL_STEP_HS   = 3,
    parameter unsigned WRITE_MIN_HS   = 100,
    parameter unsigned RESET_MIN_HS   = 100,

    // Нарезка такта счёта
    parameter unsigned HS_PER_CLK     = 10,
    parameter unsigned PHASE1_HS      = 3,
    parameter unsigned PHASE2_HS      = 4,

    parameter bit          EN_ASSERTIONS  = 1'b1
)(
    input  wire             rst_n,      // сброс логики счётчика; разряд НЕ двигает
    input  wire             clk,        // такт счёта
    input  wire             hs_clk,     // временная база модели декатронов

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
    input  wire             set,        // записать in
    input  wire             set_zero,   // сбросить в нуль
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [WIDTH-1:0] in,
/* verilator lint_on UNUSEDSIGNAL */

    // Результат
    output wire [WIDTH-1:0] out,
    output wire             out_valid,  // разряд во всех декадах установился
    output wire             zero,       // счётчик равен нулю
    output wire             at_top      // счётчик равен TOP_VALUE
);

    localparam int unsigned DW = DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Состояния
    //------------------------------------------------------------------
    localparam logic [2:0]
        ST_IDLE = 3'd0,
        ST_SET  = 3'd1,   // запись числа из защёлкнутого in
        ST_ZERO = 3'd2,   // сброс всех декад в 0
        ST_TOP  = 3'd3;   // установка всех декад в TOP_VALUE

    logic [2:0] state, next;

    //------------------------------------------------------------------
    // Состояние декад, защёлкнутое по фронту clk
    //------------------------------------------------------------------
    logic [D_NUM-1:0] dek_zero;      // комбинационно с декад
    logic [D_NUM-1:0] dek_nine;
    logic [D_NUM-1:0] dek_top;
    logic [D_NUM-1:0] dek_valid;

    logic [D_NUM-1:0] zeroes_q;      // значения ДО текущего шага
    logic [D_NUM-1:0] nines_q;
    logic [D_NUM-1:0] tops_q;
    logic             settled_q;     // все декады установились

    wire all_valid = &dek_valid;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            zeroes_q  <= '0;
            nines_q   <= '0;
            tops_q    <= '0;
            settled_q <= 1'b0;
        end
        else begin
            settled_q <= all_valid;
            // Пока разряд в пути, показания не обновляем: держим
            // последнее достоверное значение
            if (all_valid) begin
                zeroes_q <= dek_zero;
                nines_q  <= dek_nine;
                tops_q   <= dek_top;
            end
        end
    end

    assign zero      = &zeroes_q;
    assign at_top    = &tops_q;
    assign out_valid = all_valid;

    //------------------------------------------------------------------
    // Разбор операции в такте accept
    //------------------------------------------------------------------
    wire accept = valid & ready;

    // Автопереходы через край в режиме верхнего предела
    wire set_top_int;
    wire set_zero_int;

    generate
        if (TOP_LIMIT_MODE) begin : g_top_limit
            assign set_top_int  = zero   &  dec;   // 0 - 1      -> TOP_VALUE
            assign set_zero_int = at_top & ~dec;   // TOP + 1    -> 0
        end
        else begin : g_no_top_limit
            assign set_top_int  = 1'b0;
            assign set_zero_int = 1'b0;
        end
    endgenerate

    // Любая операция класса «запись»: выполняется через окно записи
    wire set_any = set | set_zero | set_top_int | set_zero_int;

    //------------------------------------------------------------------
    // Физические линии сброса
    //
    // Никакой обработки: линии идут на катодные входы декад как есть.
    // Требуемую длительность обеспечивает внешнее реле времени, поэтому
    // за время сигнала сброс гарантированно успевает отработать.
    //
    // Пока сброс активен, счётчик не готов и шаги не выдаются:
    // подкатодные импульсы во время сброса недопустимы.
    //------------------------------------------------------------------
    wire rst_active = soft_rst | hard_rst;
    wire rst_hard   = hard_rst;

    //------------------------------------------------------------------
    // Быстрый путь: шаг подаётся уровнем на весь такт accept.
    // Промежуточных состояний INC/DEC нет.
    //------------------------------------------------------------------
    wire step_f = accept & ~set_any & ~dec;
    wire step_r = accept & ~set_any &  dec;

    //------------------------------------------------------------------
    // Медленный путь: окно записи на hs_clk
    //------------------------------------------------------------------
    // Запас поверх минимальной длительности, требуемой декатроном
    localparam int unsigned WR_WINDOW_HS =
        ((WRITE_MIN_HS > RESET_MIN_HS) ? WRITE_MIN_HS : RESET_MIN_HS) + 4;

    wire write_req = accept & set_any;
    wire write_start;
    wire writing;

    Impulse writeStart (
        .Clk     (hs_clk),
        .Rst_n   (rst_n),
        .En      (write_req),
        .Impulse (write_start)
    );

    OneShot #(
        .DELAY (WR_WINDOW_HS)
    ) writeTimer (
        .Clk     (hs_clk),
        .Rst_n   (rst_n),
        .En      (write_start),
        .Impulse (writing)
    );

    //------------------------------------------------------------------
    // Защёлкивание операнда по accept
    //------------------------------------------------------------------
    logic [WIDTH-1:0] in_q;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n)
            in_q <= '0;
        else if (accept & set)
            in_q <= in;
    end

    //------------------------------------------------------------------
    // Машина состояний
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) state <= ST_IDLE;
        else        state <= next;
    end

    always_comb begin
        next = ST_IDLE;
        if (!rst_active) begin
            case (state)
                ST_IDLE: begin
                    if (accept) begin
                        // Явные операции приоритетнее автопереходов через край
                        if      (set)          next = ST_SET;
                        else if (set_zero)     next = ST_ZERO;
                        else if (set_top_int)  next = ST_TOP;
                        else if (set_zero_int) next = ST_ZERO;
                        else                   next = ST_IDLE;  // быстрый путь
                    end
                end
                ST_SET, ST_ZERO, ST_TOP: begin
                    if (writing) next = state;   // держим до конца окна записи
                end
                default: next = ST_IDLE;
            endcase
        end
    end

    // ready не зависит от valid. В быстром пути не снимается вовсе.
    assign ready = (state == ST_IDLE) & ~writing & settled_q & ~rst_active;

    //------------------------------------------------------------------
    // Линии записи на декады
    //------------------------------------------------------------------
    wire wr_set  = (state == ST_SET ) & writing;
    wire wr_zero = (state == ST_ZERO) & writing;
    wire wr_top  = (state == ST_TOP ) & writing;

    // Сброс: в старшие декады девятка, если сброс аппаратный
    wire rst_to_nine = rst_active &  rst_hard;
    wire rst_to_zero = rst_active & ~rst_hard;

    //------------------------------------------------------------------
    // Общий генератор фаз на весь счётчик
    //------------------------------------------------------------------
    wire phase1;
    wire phase2;

    DekatronPhaseGen #(
        .PHASE1_HS (PHASE1_HS),
        .PHASE2_HS (PHASE2_HS)
    ) phaseGen (
        .hsClk  (hs_clk),
        .Clk    (clk),
        .Rst_n  (rst_n),
        .Phase1 (phase1),
        .Phase2 (phase2)
    );

    //------------------------------------------------------------------
    // Декады
    //------------------------------------------------------------------
    wire [D_NUM-1:0] step_f_chain;
    wire [D_NUM-1:0] step_r_chain;

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
            localparam int unsigned RESET_N_POS_D =
                TOP_LIMIT_MODE ? int'(TOP_VALUE[(d+1)*DW-1 -: DW]) :
                (IS_HARD_DEC   ? 9 : 0);

            localparam bit EN_RESET_N_D = TOP_LIMIT_MODE || IS_HARD_DEC;


            //----------------------------------------------------------
            // Цепочка переноса. Шаг проходит дальше, если младшая декада
            // стояла на 9 (инкремент) или на 0 (декремент).
            //----------------------------------------------------------
            if (d == 0) begin : g_carry_first
                assign step_f_chain[d] = step_f;
                assign step_r_chain[d] = step_r;
            end
            else begin : g_carry_next
                assign step_f_chain[d] = step_f_chain[d-1] & nines_q [d-1];
                assign step_r_chain[d] = step_r_chain[d-1] & zeroes_q[d-1];
            end

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
                .GUIDE_STEP_HS   (GUIDE_STEP_HS),
                .FALL_STEP_HS    (FALL_STEP_HS),
                .WRITE_MIN_HS    (WRITE_MIN_HS),
                .RESET_MIN_HS    (RESET_MIN_HS),
                .HS_PER_CLK      (HS_PER_CLK),
                .PHASE1_HS       (PHASE1_HS),
                .PHASE2_HS       (PHASE2_HS),
                .EXT_PHASES      (1'b1),
                .EN_ASSERTIONS   (EN_ASSERTIONS)
            ) dModule (
                .hsClk    (hs_clk),
                .Clk      (clk),
                .Rst_n    (rst_n),
                .StepF    (step_f_chain[d]),
                .StepR    (step_r_chain[d]),
                .Phase1_i (phase1),
                .Phase2_i (phase2),
                .In       (in_q[(d+1)*DW-1 -: DW]),
                .SetData  (wr_set),
                .SetZero  (dek_set_zero),
                .SetTop   (dek_set_top),
                .Out      (out[(d+1)*DW-1 -: DW]),
                .Valid    (dek_valid[d]),
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
        if (WIDTH != D_NUM * DEKATRON_WIDTH)
            $error("DekatronCounter: WIDTH (%0d) не соответствует D_NUM*DEKATRON_WIDTH (%0d)",
                   WIDTH, D_NUM * DEKATRON_WIDTH);
        if (!WRITE)
            $display("DekatronCounter: WRITE=0, операция set недоступна (схема записи не ставится)");
    end

    generate
        if (EN_ASSERTIONS) begin : g_assertions
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
        end
    endgenerate
`endif

endmodule

`default_nettype wire
