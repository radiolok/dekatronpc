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
              DATA_TOP_VALUE = {4'd2, 4'd5, 4'd5},               // 255

    parameter bit          EN_ASSERTIONS = 1'b1
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
    output logic                                     mem_valid,
    input  wire                                      mem_ready,
    output logic                                     mem_wr,
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
    //------------------------------------------------------------------
    localparam logic [3:0]
        S_IDLE       = 4'd0,
        S_FLUSH      = 4'd1,   // выгрузка счётчика в память
        S_READ       = 4'd2,   // чтение текущей ячейки
        S_AP_OP      = 4'd3,
        S_AP_WAIT    = 4'd4,
        S_DATA_SET   = 4'd5,   // загрузка числа в счётчик данных
        S_DATA_SET_W = 4'd6,
        S_DATA_OP    = 4'd7,   // шаг или обнуление счётчика данных
        S_DATA_WAIT  = 4'd8;

    logic [3:0] state;
    logic [3:0] op_q;
    logic       dec_q;

    logic       lock_q;        // счётчик содержит значение ячейки
    logic       dirty_q;       // счётчик расходится с памятью
    logic       mem_here_q;    // регистр памяти относится к текущему адресу

    logic [DATA_W-1:0] rx_q;

    //------------------------------------------------------------------
    // Счётчик адреса данных
    //------------------------------------------------------------------
    logic           ap_valid;
    wire            ap_ready;
    logic           ap_set_zero;
    wire [AP_W-1:0] ap_out;
    wire            ap_out_valid;

    DekatronCounter #(
        .D_NUM          (AP_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b0),
        .TOP_LIMIT_MODE (1'b1),
        .TOP_VALUE      (AP_TOP_VALUE),
        .HARD_RST_D_CNT (0),
        .EN_ASSERTIONS  (EN_ASSERTIONS)
    ) ap_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (ap_valid),
        .ready     (ap_ready),
        .dec       (dec_q),
        .set       (1'b0),
        .set_zero  (ap_set_zero),
        .in        ({AP_W{1'b0}}),
        .out       (ap_out),
        .out_valid (ap_out_valid),
        .zero      (ap_zero),
        .at_top    ()
    );

    assign mem_addr = ap_out;

    //------------------------------------------------------------------
    // Счётчик данных
    //------------------------------------------------------------------
    logic              data_valid;
    wire               data_ready;
    logic              data_set;
    logic              data_set_zero;
    logic [DATA_W-1:0] data_in;
    wire [DATA_W-1:0]  data_out;
    wire               data_out_valid;
    wire               data_ctr_zero;

    DekatronCounter #(
        .D_NUM          (DATA_DEKATRON_NUM),
        .READ           (1'b1),
        .WRITE          (1'b1),
        .TOP_LIMIT_MODE (1'b1),
        .TOP_VALUE      (DATA_TOP_VALUE),
        .HARD_RST_D_CNT (0),
        .EN_ASSERTIONS  (EN_ASSERTIONS)
    ) data_counter (
        .rst_n     (rst_n),
        .clk       (clk),
        .hs_clk    (hs_clk),
        .soft_rst  (soft_rst),
        .hard_rst  (hard_rst),
        .valid     (data_valid),
        .ready     (data_ready),
        .dec       (dec_q),
        .set       (data_set),
        .set_zero  (data_set_zero),
        .in        (data_in),
        .out       (data_out),
        .out_valid (data_out_valid),
        .zero      (data_ctr_zero),
        .at_top    ()
    );

    // Значение ячейки берётся прямо из выходного регистра памяти.
    // Старшие два бита сотен восстанавливаются нулями: диапазон 0..255.
    wire [DATA_W-1:0] cell_from_mem =
        {{(DATA_W-MEM_DATA_WIDTH){1'b0}}, mem_rd_data};

    assign data_in = (op_q == OP_CIN) ? rx_q : cell_from_mem;

    //------------------------------------------------------------------
    // Наблюдаемое состояние
    //------------------------------------------------------------------
    assign mem_lock        = lock_q;
    assign mem_wr_data     = data_out[MEM_DATA_WIDTH-1:0];
    assign tx_data_bcd     = lock_q ? data_out : cell_from_mem;
    assign data_zero       = lock_q ? data_ctr_zero : ~(|cell_from_mem);
    assign data_zero_valid = lock_q | mem_here_q;

    assign ready = (state == S_IDLE) & ap_ready & data_ready & mem_ready;

    wire accept = valid & ready;

    // Нужно ли значение ячейки для этой операции
    wire need_cell = (op == OP_DATA_STEP) | (op == OP_COUT) |
                     (op == OP_LOAD)      | (op == OP_TEST);

    //------------------------------------------------------------------
    // Основной автомат
    //------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            state         <= S_IDLE;
            op_q          <= OP_NOP;
            dec_q         <= 1'b0;
            lock_q        <= 1'b0;
            dirty_q       <= 1'b0;
            mem_here_q    <= 1'b0;
            rx_q          <= '0;
            ap_valid      <= 1'b0;
            ap_set_zero   <= 1'b0;
            data_valid    <= 1'b0;
            data_set      <= 1'b0;
            data_set_zero <= 1'b0;
            mem_valid     <= 1'b0;
            mem_wr        <= 1'b0;
        end
        else begin
            ap_valid   <= 1'b0;
            data_valid <= 1'b0;
            mem_valid  <= 1'b0;

            // Физический сброс счётчиков: адрес ушёл в нуль, содержимое
            // выходного регистра памяти к нему не относится
            if (soft_rst | hard_rst) begin
                state         <= S_IDLE;
                lock_q        <= 1'b0;
                dirty_q       <= 1'b0;
                mem_here_q    <= 1'b0;
                ap_set_zero   <= 1'b0;
                data_set      <= 1'b0;
                data_set_zero <= 1'b0;
                mem_wr        <= 1'b0;
            end
            else begin
                case (state)

                //------------------------------------------------------
                S_IDLE: begin
                    if (accept) begin
                        op_q  <= op;
                        dec_q <= dec;
                        rx_q  <= rx_data_bcd;

                        case (op)

                        OP_AP_STEP, OP_AP_ZERO: begin
                            ap_set_zero <= (op == OP_AP_ZERO);
                            if (dirty_q) begin
                                // Выгружаем только изменённое значение
                                mem_valid <= 1'b1;
                                mem_wr    <= 1'b1;
                                state     <= S_FLUSH;
                            end
                            else begin
                                ap_valid <= 1'b1;
                                state    <= S_AP_OP;
                            end
                        end

                        OP_DATA_STEP: begin
                            if (lock_q) begin
                                data_valid <= 1'b1;
                                state      <= S_DATA_OP;
                            end
                            else if (mem_here_q) begin
                                // Значение уже в регистре памяти
                                data_set   <= 1'b1;
                                data_valid <= 1'b1;
                                state      <= S_DATA_SET;
                            end
                            else begin
                                mem_valid <= 1'b1;
                                mem_wr    <= 1'b0;
                                state     <= S_READ;
                            end
                        end

                        OP_DATA_ZERO: begin
                            data_set_zero <= 1'b1;
                            data_valid    <= 1'b1;
                            lock_q        <= 1'b1;
                            dirty_q       <= 1'b1;
                            state         <= S_DATA_OP;
                        end

                        OP_CIN: begin
                            data_set   <= 1'b1;
                            data_valid <= 1'b1;
                            lock_q     <= 1'b1;
                            dirty_q    <= 1'b1;
                            state      <= S_DATA_SET;
                        end

                        OP_COUT, OP_TEST: begin
                            // Достаточно, чтобы значение было доступно:
                            // в счётчике либо в регистре памяти
                            if (lock_q | mem_here_q) begin
                                state <= S_IDLE;
                            end
                            else begin
                                mem_valid <= 1'b1;
                                mem_wr    <= 1'b0;
                                state     <= S_READ;
                            end
                        end

                        OP_LOAD: begin
                            // MemLock не меняется
                            if (mem_here_q) begin
                                data_set   <= 1'b1;
                                data_valid <= 1'b1;
                                state      <= S_DATA_SET;
                            end
                            else begin
                                mem_valid <= 1'b1;
                                mem_wr    <= 1'b0;
                                state     <= S_READ;
                            end
                        end

                        OP_STORE: begin
                            mem_valid <= 1'b1;
                            mem_wr    <= 1'b1;
                            state     <= S_FLUSH;
                        end

                        OP_CLRML: begin
                            if (dirty_q) begin
                                mem_valid <= 1'b1;
                                mem_wr    <= 1'b1;
                                state     <= S_FLUSH;
                            end
                            else begin
                                lock_q <= 1'b0;
                            end
                        end

                        default: ;   // OP_NOP
                        endcase
                    end
                end

                //------------------------------------------------------
                // Чтение текущей ячейки
                //------------------------------------------------------
                S_READ: begin
                    if (mem_ready & mem_rd_valid) begin
                        mem_here_q <= 1'b1;

                        case (op_q)
                            OP_DATA_STEP, OP_LOAD: begin
                                data_set   <= 1'b1;
                                data_valid <= 1'b1;
                                state      <= S_DATA_SET;
                            end
                            default: state <= S_IDLE;   // COUT, TEST
                        endcase
                    end
                    else if (~mem_ready) begin
                        // обращение выполняется
                    end
                    else begin
                        mem_valid <= 1'b1;    // удерживаем до приёма
                        mem_wr    <= 1'b0;
                    end
                end

                //------------------------------------------------------
                // Выгрузка счётчика в память
                //------------------------------------------------------
                S_FLUSH: begin
                    if (mem_ready & mem_rd_valid) begin
                        // Сквозная запись: регистр памяти уже содержит
                        // выгруженное значение
                        mem_wr     <= 1'b0;
                        dirty_q    <= 1'b0;
                        mem_here_q <= 1'b1;

                        case (op_q)
                            OP_AP_STEP, OP_AP_ZERO: begin
                                lock_q   <= 1'b0;
                                ap_valid <= 1'b1;
                                state    <= S_AP_OP;
                            end
                            OP_CLRML: begin
                                lock_q <= 1'b0;
                                state  <= S_IDLE;
                            end
                            default: state <= S_IDLE;   // OP_STORE
                        endcase
                    end
                    else if (~mem_ready) begin
                        // обращение выполняется
                    end
                    else begin
                        mem_valid <= 1'b1;
                        mem_wr    <= 1'b1;
                    end
                end

                //------------------------------------------------------
                // Шаг счётчика адреса
                //------------------------------------------------------
                S_AP_OP: begin
                    if (ap_ready) begin
                        ap_set_zero <= 1'b0;
                        state       <= S_AP_WAIT;
                    end
                    else ap_valid <= 1'b1;
                end

                S_AP_WAIT: begin
                    if (ap_ready & ap_out_valid) begin
                        // Ячейка сменилась: регистр памяти к ней не относится.
                        // Читать заранее не будем — понадобится, тогда и прочтём.
                        mem_here_q <= 1'b0;
                        state      <= S_IDLE;
                    end
                end

                //------------------------------------------------------
                // Загрузка числа в счётчик данных
                //------------------------------------------------------
                S_DATA_SET: begin
                    if (data_ready) begin
                        data_set <= 1'b0;
                        state    <= S_DATA_SET_W;
                    end
                    else data_valid <= 1'b1;
                end

                S_DATA_SET_W: begin
                    if (data_ready & data_out_valid) begin
                        case (op_q)
                            OP_DATA_STEP: begin
                                lock_q     <= 1'b1;
                                data_valid <= 1'b1;
                                state      <= S_DATA_OP;
                            end
                            OP_LOAD: state <= S_IDLE;   // MemLock не меняется
                            default: state <= S_IDLE;   // OP_CIN
                        endcase
                    end
                end

                //------------------------------------------------------
                // Шаг или обнуление счётчика данных
                //------------------------------------------------------
                S_DATA_OP: begin
                    if (data_ready) begin
                        data_set_zero <= 1'b0;
                        state         <= S_DATA_WAIT;
                    end
                    else data_valid <= 1'b1;
                end

                S_DATA_WAIT: begin
                    if (data_ready & data_out_valid) begin
                        if (op_q == OP_DATA_STEP) begin
                            lock_q  <= 1'b1;
                            dirty_q <= 1'b1;
                        end
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTH
    generate
        if (EN_ASSERTIONS) begin : g_assertions
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
        end
    endgenerate
`endif

endmodule

`default_nettype wire
