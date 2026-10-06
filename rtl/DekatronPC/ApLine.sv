//======================================================================
// ApLine — блок работы с данными
//----------------------------------------------------------------------
// Счётчик адреса, счётчик данных и обмен с памятью данных.
// Вышестоящему блоку предоставляет Valid/Ready.
//
//----------------------------------------------------------------------
// ЛЕНИВОЕ ЧТЕНИЕ
//
// Ячейка читается только тогда, когда её значение действительно нужно.
// Смена адреса чтения НЕ вызывает: последовательность шагов указателя
// не обращается к памяти вовсе.
//
// Замер на программе вычисления Pi, где перемещения указателя составляют
// половину инструкций: 99 077 обращений к памяти против 155 625 при
// упреждающем чтении, то есть на 36% меньше.
//
// Собственной копии ячейки блок не хранит. Значение держит выходной
// регистр памяти, который сохраняет содержимое последней затронутой
// ячейки до следующего обращения. Это тот самый регистр, который у
// ферритовой памяти существует физически: считанное значение оседает в
// усилителях считывания на время восстановительной записи.
//
//----------------------------------------------------------------------
// СОСТОЯНИЕ БЛОКА — ТРИ БИТА
//
//   lock_q     счётчик данных содержит значение текущей ячейки
//   dirty_q    счётчик расходится с памятью, выгрузка обязательна
//   mem_here_q выходной регистр памяти относится к ТЕКУЩЕМУ адресу
//
// Выгрузка выполняется только при dirty_q. Явная загрузка или вывод не
// делают ячейку грязной, поэтому лишней записи при уходе с неё нет.
//
//----------------------------------------------------------------------
// ПРИЗНАК НУЛЯ
//
// data_zero берётся из счётчика при lock_q и из выходного регистра
// памяти иначе. Он достоверен при lock_q | mem_here_q; обеспечить это
// перед проверкой цикла обязан вышестоящий блок операцией OP_TEST.
//======================================================================

`default_nettype none

module ApLine #(
    // Ячейка памяти данных: {hundreds[1:0], tens[3:0], ones[3:0]}
    parameter unsigned MEM_DATA_WIDTH    = 10,

    parameter [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]
              AP_TOP_VALUE   = {4'd2, 4'd9, 4'd9, 4'd9, 4'd9},   // 29999
    parameter [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0]
              DATA_TOP_VALUE = {4'd2, 4'd5, 4'd5}                // 255
)(
    input  wire rst_n,
    input  wire clk,
    input  wire hs_clk,

    input  wire soft_rst,
    input  wire hard_rst,

    //------------------------------------------------------------------
    // Командный интерфейс
    //------------------------------------------------------------------
    input  wire       valid,
    output wire       ready,
    input  wire [3:0] op,
    input  wire       dec,

    //------------------------------------------------------------------
    // Состояние для блока управления
    //------------------------------------------------------------------
    output wire       data_zero,
    output wire       data_zero_valid,
    output wire       ap_zero,
    output wire       mem_lock,

    //------------------------------------------------------------------
    // Терминал
    //------------------------------------------------------------------
    input  wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd,

    //------------------------------------------------------------------
    // Память данных, Valid/Ready
    //------------------------------------------------------------------
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] mem_addr,
    output wire [MEM_DATA_WIDTH-1:0]                 mem_wr_data,
    input  wire [MEM_DATA_WIDTH-1:0]                 mem_rd_data,
    output wire                                      mem_valid,
    input  wire                                      mem_ready,
    output wire                                      mem_wr,
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                                      mem_rd_valid,
    input  wire                                      mem_err
/* verilator lint_on UNUSEDSIGNAL */
);

    localparam int unsigned AP_W   = AP_DEKATRON_NUM   * DEKATRON_WIDTH;
    localparam int unsigned DATA_W = DATA_DEKATRON_NUM * DEKATRON_WIDTH;

    //------------------------------------------------------------------
    // Коды операций
    //------------------------------------------------------------------
    localparam logic [3:0]
        OP_NOP       = 4'd0,
        OP_AP_STEP   = 4'd1,   // >  <
        OP_AP_ZERO   = 4'd2,   // CLRA
        OP_DATA_STEP = 4'd3,   // +  -
        OP_DATA_ZERO = 4'd4,   // CLRD, [-]
        OP_CIN       = 4'd5,   // ,
        OP_COUT      = 4'd6,   // .
        OP_LOAD      = 4'd7,   // LOAD
        OP_STORE     = 4'd8,   // STORE
        OP_CLRML     = 4'd9,   // CLRML
        OP_TEST      = 4'd10;  // обеспечить достоверность признака нуля

    //------------------------------------------------------------------
    // Состояния
    //
    // Каждое состояние, кроме S_IDLE, выдаёт ровно одну операцию одному
    // исполнителю и покидает себя в такте её приёма. Ожидания окончания
    // операции (прежние пары OP/WAIT) нет: следующее состояние, как и
    // S_IDLE, само ждёт go — готовности всех трёх исполнителей.
    //------------------------------------------------------------------
    localparam logic [2:0]
        S_IDLE  = 3'd0,
        S_FLUSH = 3'd1,   // выгрузка счётчика в память
        S_READ  = 3'd2,   // чтение текущей ячейки
        S_AP    = 3'd3,   // шаг или обнуление счётчика адреса
        S_DSET  = 3'd4,   // загрузка числа в счётчик данных
        S_DOP   = 3'd5;   // шаг или обнуление счётчика данных

    logic [2:0] state;

    logic       lock_q;        // счётчик содержит значение ячейки
    logic       dirty_q;       // счётчик расходится с памятью
    logic       mem_here_q;    // регистр памяти относится к текущему адресу

    //------------------------------------------------------------------
    // Счётчик адреса данных
    //------------------------------------------------------------------
    wire            ap_valid;
    wire            ap_ready;
    wire            ap_set_zero;
    wire [AP_W-1:0] ap_out;

    DekatronCounter #(
        .D_NUM          (AP_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b0),
        .TOP_LIMIT_MODE (1'b0),
        .HARD_RST_D_CNT (0)
    ) ap_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (ap_valid),
        .ready     (ap_ready),
        .dec       (dec),
        .set       (1'b0),
        .set_zero  (ap_set_zero),
        .in        ({AP_W{1'b0}}),
        .out       (ap_out),
        .zero      (ap_zero),
        .at_top    ()
    );

    assign mem_addr = ap_out;

    //------------------------------------------------------------------
    // Счётчик данных
    //------------------------------------------------------------------
    wire               data_valid;
    wire               data_ready;
    wire               data_set;
    wire               data_set_zero;
    wire  [DATA_W-1:0] data_in;
    wire [DATA_W-1:0]  data_out;
    wire               data_ctr_zero;

    DekatronCounter #(
        .D_NUM          (DATA_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b1),
        .TOP_LIMIT_MODE (1'b1),
        .TOP_VALUE      (DATA_TOP_VALUE),
        .HARD_RST_D_CNT (0)
    ) data_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (data_valid),
        .ready     (data_ready),
        .dec       (dec),
        .set       (data_set),
        .set_zero  (data_set_zero),
        .in        (data_in),
        .out       (data_out),
        .zero      (data_ctr_zero),
        .at_top    ()
    );

    // Значение ячейки берётся прямо из выходного регистра памяти.
    // Старшие два бита сотен восстанавливаются нулями: диапазон 0..255.
    wire [DATA_W-1:0] cell_from_mem =
        {{(DATA_W-MEM_DATA_WIDTH){1'b0}}, mem_rd_data};

    // Символ терминала не защёлкивается: передающая сторона держит
    // rx_data_bcd до рукопожатия rx_vld & rx_rdy, а rx_rdy верхний автомат
    // выдаёт только по завершении CIN, когда запись в счётчик окончена
    // (REQ-UART-008). op мастер держит до ready.
    assign data_in = (op == OP_CIN) ? rx_data_bcd : cell_from_mem;

    //------------------------------------------------------------------
    // Наблюдаемое состояние
    //------------------------------------------------------------------
    assign mem_lock        = lock_q;
    assign mem_wr_data     = data_out[MEM_DATA_WIDTH-1:0];
    assign tx_data_bcd     = lock_q ? data_out : cell_from_mem;
    assign data_zero       = lock_q ? data_ctr_zero : ~(|cell_from_mem);
    assign data_zero_valid = lock_q | mem_here_q;

    //------------------------------------------------------------------
    // Готовность исполнителей
    //
    // Память отдаёт ready вместе с данными: rd_data достоверен, как только
    // ready вернулся после приёма чтения, и держится до следующего
    // обращения. Поэтому окончание любой операции определяется одним
    // go, а mem_rd_valid не нужен.
    //------------------------------------------------------------------
    wire go = ap_ready & data_ready & mem_ready;

    assign ready = (state == S_IDLE) & go;

    wire accept = valid & ready;

    //------------------------------------------------------------------
    // Стробы исполнителям — дешифрация состояния (автомат Мура)
    //
    // valid поднимается только при go, то есть при уже поднятом ready
    // исполнителя, и рукопожатие происходит в том же такте: valid не
    // бывает выставлен без приёма. ready исполнителей от valid не
    // зависят, петли нет. Признаки операции (set_zero, set, wr) значимы
    // только вместе с valid, поэтому берутся из op и state без go.
    //------------------------------------------------------------------
    wire in_flush = (state == S_FLUSH);
    wire in_read  = (state == S_READ);
    wire in_ap    = (state == S_AP);
    wire in_dset  = (state == S_DSET);
    wire in_dop   = (state == S_DOP);

    assign ap_valid      = in_ap & go;
    assign ap_set_zero   = (op == OP_AP_ZERO);
    assign data_valid    = (in_dset | in_dop) & go;
    assign data_set      = in_dset;
    assign data_set_zero = (op == OP_DATA_ZERO);
    assign mem_valid     = (in_flush | in_read) & go;
    assign mem_wr        = in_flush;

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state      <= S_IDLE;
            lock_q     <= 1'b0;
            dirty_q    <= 1'b0;
            mem_here_q <= 1'b0;
        end
        // Физический сброс счётчиков: адрес ушёл в нуль, содержимое
        // выходного регистра памяти к нему не относится
        else if (soft_rst | hard_rst) begin
            state      <= S_IDLE;
            lock_q     <= 1'b0;
            dirty_q    <= 1'b0;
            mem_here_q <= 1'b0;
        end
        else begin
            case (state)

            //----------------------------------------------------------
            S_IDLE: begin
                if (accept) begin
                    case (op)

                    // Выгружаем только изменённое значение
                    OP_AP_STEP, OP_AP_ZERO:
                        state <= dirty_q ? S_FLUSH : S_AP;

                    OP_DATA_STEP:
                        if (lock_q)          state <= S_DOP;
                        else if (mem_here_q) state <= S_DSET;  // значение уже в регистре памяти
                        else                 state <= S_READ;

                    OP_DATA_ZERO:
                        state <= S_DOP;

                    OP_CIN: begin
                        lock_q  <= 1'b1;
                        dirty_q <= 1'b1;
                        state   <= S_DSET;
                    end

                    // Достаточно, чтобы значение было доступно:
                    // в счётчике либо в регистре памяти
                    OP_COUT, OP_TEST:
                        if (~(lock_q | mem_here_q)) state <= S_READ;

                    // MemLock не меняется
                    OP_LOAD:
                        state <= mem_here_q ? S_DSET : S_READ;

                    OP_STORE:
                        state <= S_FLUSH;

                    OP_CLRML:
                        if (dirty_q) state  <= S_FLUSH;
                        else         lock_q <= 1'b0;

                    default: ;   // OP_NOP
                    endcase
                end
            end

            //----------------------------------------------------------
            // Чтение текущей ячейки
            //----------------------------------------------------------
            S_READ: begin
                if (go) begin
                    mem_here_q <= 1'b1;
                    state <= ((op == OP_DATA_STEP) | (op == OP_LOAD))
                           ? S_DSET : S_IDLE;           // COUT, TEST
                end
            end

            //----------------------------------------------------------
            // Выгрузка счётчика в память. Сквозная запись: регистр
            // памяти после неё содержит выгруженное значение
            //----------------------------------------------------------
            S_FLUSH: begin
                if (go) begin
                    dirty_q    <= 1'b0;
                    mem_here_q <= 1'b1;
                    case (op)
                        OP_AP_STEP, OP_AP_ZERO: begin
                            lock_q <= 1'b0;
                            state  <= S_AP;
                        end
                        OP_CLRML: begin
                            lock_q <= 1'b0;
                            state  <= S_IDLE;
                        end
                        default: state <= S_IDLE;   // OP_STORE
                    endcase
                end
            end

            //----------------------------------------------------------
            // Шаг счётчика адреса. Ячейка сменилась: регистр памяти к
            // ней не относится. Читать заранее не будем — понадобится,
            // тогда и прочтём.
            //----------------------------------------------------------
            S_AP: begin
                if (go) begin
                    mem_here_q <= 1'b0;
                    state      <= S_IDLE;
                end
            end

            //----------------------------------------------------------
            // Загрузка числа в счётчик данных: из регистра памяти
            // (+, LOAD) или с терминала (CIN)
            //----------------------------------------------------------
            S_DSET: begin
                if (go)
                    state <= (op == OP_DATA_STEP) ? S_DOP : S_IDLE;
            end

            //----------------------------------------------------------
            // Шаг (+ -) или обнуление (CLRD) счётчика данных: после
            // них счётчик держит ячейку и расходится с памятью
            //----------------------------------------------------------
            S_DOP: begin
                if (go) begin
                    lock_q  <= 1'b1;
                    dirty_q <= 1'b1;
                    state   <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTH
`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && valid && (op > OP_TEST))
            $error("ApLine: неизвестный код операции %0d", op);
        if (rst_n && $past(valid) && !$past(ready) && !valid)
            $error("ApLine: valid снят до handshake");
        if (rst_n && mem_err)
            $error("ApLine: ошибка обращения к памяти данных");
        // Грязный счётчик обязан быть захвачен
        if (rst_n && dirty_q && !lock_q)
            $error("ApLine: dirty без lock — значение будет потеряно");
    end
`endif
`endif

endmodule

`default_nettype wire
