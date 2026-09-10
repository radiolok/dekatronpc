//======================================================================
// Ram — банковая память с интерфейсом Valid/Ready
//----------------------------------------------------------------------
// Организация повторяет физическую структуру машины:
//
//   RamBank            банк 10x10, 100 ячеек        2 декатрона
//   RamGroup LEVEL=1   10 банков,  1 000 ячеек      3 декатрона
//   RamGroup LEVEL=2   10 групп,   10 000 ячеек     4 декатрона
//   RamGroup LEVEL=3   10 групп,   100 000 ячеек    5 декатронов
//
// Адрес приходит в BCD, по тетраде на декатрон. Тетрада напрямую
// выбирает потомка сравнением, адресной арифметики нет.
//
//----------------------------------------------------------------------
// ВЫХОДНОЙ РЕГИСТР
//
// rd_data — регистр, а не комбинационный выход шины. Он хранит значение
// последней затронутой ячейки и держит его до следующего обращения.
//
// Так устроена и настоящая ферритовая память: чтение разрушающее,
// считанное значение оседает в усилителях считывания и остаётся там,
// пока идёт восстановительная запись. Регистр не добавлен ради удобства,
// а перенесён туда, где он физически существует. Благодаря этому
// вышестоящим блокам не нужна собственная копия ячейки.
//
// Запись сквозная: после записи выходной регистр содержит записанное
// значение, поэтому обратное чтение той же ячейки не требуется.
//
// rd_valid снимается на время выполнения обращения и поднимается по его
// завершении. Соответствие регистра нужному адресу отслеживает мастер:
// память знает лишь то, что регистр относится к последнему обращению.
//
//----------------------------------------------------------------------
// НАЛОЖЕНИЕ ПОСТОЯННОЙ ПАМЯТИ
//
// Входы ovl_* позволяют наложить область ПЗУ поверх адресного
// пространства, не дублируя автомат обращений. Этим пользуется память
// программ, где старший банк занят начальным загрузчиком.
//======================================================================
//verilator lint_off DECLFILENAME
`default_nettype none

//----------------------------------------------------------------------
// RamBank — банк 10x10, физическая единица памяти
//----------------------------------------------------------------------
module RamBank #(
    parameter unsigned DATA_WIDTH  = 10,
    parameter bit          INIT_ZERO   = 1'b1,
    parameter bit          EN_DBG_PORT = 1'b0
)(
    input  wire                    clk,

    input  wire [3:0]              row_i,       // BCD, десятки
    input  wire [3:0]              col_i,       // BCD, единицы
    input  wire                    sel_i,
    input  wire                    wr_i,
    input  wire [DATA_WIDTH-1:0]   wr_data_i,
    output wire [DATA_WIDTH-1:0]   rd_data_o,

    // Второй порт чтения — только для индикации в эмуляторе
    input  wire [3:0]              dbg_row_i,
    input  wire [3:0]              dbg_col_i,
    input  wire                    dbg_sel_i,
    output wire [DATA_WIDTH-1:0]   dbg_data_o
);

    logic [DATA_WIDTH-1:0] mem [0:9][0:9];

    wire row_ok = (row_i <= 4'd9);
    wire col_ok = (col_i <= 4'd9);
    wire hit    = sel_i & row_ok & col_ok;

    wire [3:0] r = row_ok ? row_i : 4'd0;
    wire [3:0] c = col_ok ? col_i : 4'd0;

    always_ff @(posedge clk) begin
        if (hit & wr_i)
            mem[r][c] <= wr_data_i;
    end

    assign rd_data_o = hit ? mem[r][c] : '0;

    generate
        if (EN_DBG_PORT) begin : g_dbg
            wire dbg_row_ok = (dbg_row_i <= 4'd9);
            wire dbg_col_ok = (dbg_col_i <= 4'd9);
            wire dbg_hit    = dbg_sel_i & dbg_row_ok & dbg_col_ok;
            wire [3:0] dr = dbg_row_ok ? dbg_row_i : 4'd0;
            wire [3:0] dc = dbg_col_ok ? dbg_col_i : 4'd0;
            assign dbg_data_o = dbg_hit ? mem[dr][dc] : '0;
        end
        else begin : g_no_dbg
            assign dbg_data_o = '0;
        end
    endgenerate

    generate
        if (INIT_ZERO) begin : g_init
            initial begin
                for (int i = 0; i < 10; i++)
                    for (int j = 0; j < 10; j++)
                        mem[i][j] = '0;
            end
        end
    endgenerate

endmodule


//----------------------------------------------------------------------
// RamGroup — рекурсивная группа из десяти потомков
//----------------------------------------------------------------------
module RamGroup #(
    parameter unsigned DATA_WIDTH  = 10,
    parameter unsigned LEVEL       = 3,
    parameter bit          INIT_ZERO   = 1'b1,
    parameter bit          EN_DBG_PORT = 1'b0,
    parameter unsigned ADDR_WIDTH  = 4 * (LEVEL + 2)
)(
    input  wire                    clk,
    input  wire [ADDR_WIDTH-1:0]   addr_i,
    input  wire                    sel_i,
    input  wire                    wr_i,
    input  wire [DATA_WIDTH-1:0]   wr_data_i,
    output wire [DATA_WIDTH-1:0]   rd_data_o,

    input  wire [ADDR_WIDTH-1:0]   dbg_addr_i,
    input  wire                    dbg_sel_i,
    output wire [DATA_WIDTH-1:0]   dbg_data_o
);

    generate
        if (LEVEL == 0) begin : g_bank

            RamBank #(
                .DATA_WIDTH  (DATA_WIDTH),
                .INIT_ZERO   (INIT_ZERO),
                .EN_DBG_PORT (EN_DBG_PORT)
            ) bank (
                .clk        (clk),
                .row_i      (addr_i[7:4]),
                .col_i      (addr_i[3:0]),
                .sel_i      (sel_i),
                .wr_i       (wr_i),
                .wr_data_i  (wr_data_i),
                .rd_data_o  (rd_data_o),
                .dbg_row_i  (dbg_addr_i[7:4]),
                .dbg_col_i  (dbg_addr_i[3:0]),
                .dbg_sel_i  (dbg_sel_i),
                .dbg_data_o (dbg_data_o)
            );

        end
        else begin : g_group

            localparam int unsigned CHILD_AW = 4 * (LEVEL + 1);

            wire [3:0] digit     = addr_i    [ADDR_WIDTH-1 -: 4];
            wire [3:0] dbg_digit = dbg_addr_i[ADDR_WIDTH-1 -: 4];

            logic [DATA_WIDTH-1:0] child_rd  [0:9];
            logic [DATA_WIDTH-1:0] child_dbg [0:9];

            genvar i;
            for (i = 0; i < 10; i++) begin : child
                wire child_sel     = sel_i     & (digit     == 4'(i));
                wire child_dbg_sel = dbg_sel_i & (dbg_digit == 4'(i));

                RamGroup #(
                    .DATA_WIDTH  (DATA_WIDTH),
                    .LEVEL       (LEVEL - 1),
                    .INIT_ZERO   (INIT_ZERO),
                    .EN_DBG_PORT (EN_DBG_PORT)
                ) grp (
                    .clk        (clk),
                    .addr_i     (addr_i[CHILD_AW-1:0]),
                    .sel_i      (child_sel),
                    .wr_i       (wr_i),
                    .wr_data_i  (wr_data_i),
                    .rd_data_o  (child_rd[i]),
                    .dbg_addr_i (dbg_addr_i[CHILD_AW-1:0]),
                    .dbg_sel_i  (child_dbg_sel),
                    .dbg_data_o (child_dbg[i])
                );
            end

            logic [DATA_WIDTH-1:0] rd_or, dbg_or;
            always_comb begin
                rd_or  = '0;
                dbg_or = '0;
                for (int k = 0; k < 10; k++) begin
                    rd_or  |= child_rd [k];
                    dbg_or |= child_dbg[k];
                end
            end

            assign rd_data_o  = rd_or;
            assign dbg_data_o = dbg_or;
        end
    endgenerate

endmodule


//----------------------------------------------------------------------
// Ram — обёртка с интерфейсом Valid/Ready
//----------------------------------------------------------------------
module Ram #(
    parameter unsigned D_NUM         = 5,
    parameter unsigned DATA_WIDTH    = 10,
    parameter unsigned READ_CYCLES   = 1,
    parameter unsigned WRITE_CYCLES  = 1,
    parameter bit          INIT_ZERO     = 1'b1,
    parameter bit          EN_DBG_PORT   = 1'b0,
    parameter bit          EN_OVERLAY    = 1'b0,   // наложение ПЗУ
    parameter bit          EN_ASSERTIONS = 1'b1,
    parameter unsigned ADDR_WIDTH    = 4 * D_NUM
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Valid/Ready
    input  wire                     valid,
    output wire                     ready,
    input  wire                     wr,
    input  wire [ADDR_WIDTH-1:0]    addr,        // BCD
    input  wire [DATA_WIDTH-1:0]    wr_data,

    // Выходной регистр: держит значение последней затронутой ячейки
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_valid,
    output logic                    err,

    // Наложение ПЗУ, действует при EN_OVERLAY
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                     ovl_hit,     // адрес попал в ПЗУ
    input  wire [DATA_WIDTH-1:0]    ovl_data,    // содержимое ПЗУ
/* verilator lint_on UNUSEDSIGNAL */

    // Второй порт чтения — только эмулятор
    input  wire [ADDR_WIDTH-1:0]    dbg_addr,
    output wire [DATA_WIDTH-1:0]    dbg_data
);

    localparam int unsigned CNT_W = 8;

    //------------------------------------------------------------------
    // Приём запроса
    //------------------------------------------------------------------
    logic                  busy;
    logic [CNT_W-1:0]      cnt;
    logic                  wr_q;
    logic [ADDR_WIDTH-1:0] addr_q;
    logic [DATA_WIDTH-1:0] wr_data_q;
    logic                  ovl_hit_q;
    logic [DATA_WIDTH-1:0] ovl_data_q;
    logic                  err_q;

    assign ready = ~busy;

    wire accept = valid & ready;

    // Недопустимые тетрады адреса
    logic bcd_err;
    always_comb begin
        bcd_err = 1'b0;
        for (int d = 0; d < int'(D_NUM); d++)
            if (addr[4*d +: 4] > 4'd9)
                bcd_err = 1'b1;
    end

    // Запись в область ПЗУ не выполняется
    wire ovl_active  = EN_OVERLAY & ovl_hit;
    wire wr_to_rom   = wr & ovl_active;
    wire req_err     = bcd_err | wr_to_rom;

    wire [CNT_W-1:0] target = wr ? CNT_W'(WRITE_CYCLES) : CNT_W'(READ_CYCLES);
    wire done = ((cnt + CNT_W'(1)) >= (wr_q ? CNT_W'(WRITE_CYCLES)
                                            : CNT_W'(READ_CYCLES)));

    // Запись в массив выполняется в такте завершения обращения
    wire mem_we = busy & done & wr_q & ~err_q;

    wire [DATA_WIDTH-1:0] bank_rd;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            busy       <= 1'b0;
            cnt        <= '0;
            wr_q       <= 1'b0;
            addr_q     <= '0;
            wr_data_q  <= '0;
            ovl_hit_q  <= 1'b0;
            ovl_data_q <= '0;
            err_q      <= 1'b0;
            rd_data    <= '0;
            rd_valid   <= 1'b0;
            err        <= 1'b0;
        end
        else if (~busy) begin
            if (accept) begin
                busy       <= 1'b1;
                cnt        <= CNT_W'(1);
                wr_q       <= wr;
                addr_q     <= addr;
                wr_data_q  <= wr_data;
                ovl_hit_q  <= ovl_active;
                ovl_data_q <= ovl_data;
                err_q      <= req_err;
                rd_valid   <= 1'b0;      // регистр перестал быть достоверным
                err        <= 1'b0;
            end
        end
        else begin
            if (done) begin
                busy     <= 1'b0;
                cnt      <= '0;
                rd_valid <= 1'b1;
                err      <= err_q;

                if (err_q) begin
                    // Обращение не выполнено, регистр не меняем
                    rd_valid <= 1'b0;
                end
                else if (wr_q) begin
                    // Сквозная запись: регистр содержит записанное значение
                    rd_data <= wr_data_q;
                end
                else begin
                    rd_data <= ovl_hit_q ? ovl_data_q : bank_rd;
                end
            end
            else begin
                cnt <= cnt + CNT_W'(1);
            end
        end
    end

    //------------------------------------------------------------------
    // Дерево банков. Адрес защёлкнут, поэтому стабилен всё обращение.
    //------------------------------------------------------------------
    RamGroup #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LEVEL       (D_NUM - 2),
        .INIT_ZERO   (INIT_ZERO),
        .EN_DBG_PORT (EN_DBG_PORT)
    ) top (
        .clk        (clk),
        .addr_i     (addr_q),
        .sel_i      (busy),
        .wr_i       (mem_we),
        .wr_data_i  (wr_data_q),
        .rd_data_o  (bank_rd),
        .dbg_addr_i (dbg_addr),
        .dbg_sel_i  (EN_DBG_PORT),
        .dbg_data_o (dbg_data)
    );

`ifndef SYNTH
    initial begin
        if (D_NUM < 2)
            $error("Ram: D_NUM (%0d) < 2 — минимальная единица это банк 10x10", D_NUM);
        if (READ_CYCLES == 0 || WRITE_CYCLES == 0)
            $error("Ram: READ_CYCLES и WRITE_CYCLES должны быть >= 1");
        if (D_NUM > 3)
            $display("Ram: D_NUM=%0d даёт %0d банков — структура для симуляции и P&R; для FPGA нужна плоская реализация",
                     D_NUM, 10**(D_NUM-2));
    end

    generate
        if (EN_ASSERTIONS) begin : g_assertions
            always @(posedge clk) begin
                if (rst_n && err)
                    $error("Ram: недопустимое обращение по адресу %h", addr_q);
                if (rst_n && accept && $isunknown({addr, wr}))
                    $error("Ram: неопределённые значения на входах запроса");
            end
        end
    endgenerate
`endif

    /* verilator lint_off UNUSEDSIGNAL */
    wire [CNT_W-1:0] unused_target = target;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

`default_nettype wire
