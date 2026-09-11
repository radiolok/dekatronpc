//======================================================================
// Ram — банковая память с интерфейсом Valid/Ready
//----------------------------------------------------------------------
// Организация повторяет физическую структуру машины: дерево банков,
// где каждая тетрада адреса выбирает потомка сравнением. Адресной
// арифметики между уровнями нет.
//
//----------------------------------------------------------------------
// РАЗМЕР БАНКА
//
// BANK_DIGITS задаёт, сколько младших тетрад адресуют ячейку внутри
// банка, то есть где рекурсия останавливается:
//
//   BANK_DIGITS = 2   банк 10x10,     100 ячеек
//   BANK_DIGITS = 4   банк 100x100,   10 000 ячеек
//
// Два варианта нужны для разных целей.
//
// Физическая машина и P&R: BANK_DIGITS = 2. Банк 10x10 — это матрица
// сердечников с дешифраторами на десять строковых и десять столбцовых
// линий, по тетраде на каждый.
//
// FPGA-эмулятор: BANK_DIGITS = 4. При банке 10x10 массив занимает
// 400 бит, а блок памяти ПЛИС вмещает 10 240: пропадает 96% каждого
// блока, и на две памяти требуется около 1300 блоков вместо 80 по
// объёму. Банк 100x100 использует блоки целиком.
//
//----------------------------------------------------------------------
// СИНХРОННОЕ ЧТЕНИЕ
//
// Выходной регистр стоит ВНУТРИ банка. Это не оптимизация, а условие
// работоспособности: блоки памяти ПЛИС умеют только синхронное чтение,
// и при асинхронном массив раскладывается в триггеры — 700 000 штук
// при бюджете порядка 40 000 логических элементов.
//
// Заодно регистр даёт нужную семантику даром: блок хранит прочитанное,
// пока не придёт следующее обращение. Так же ведёт себя и ферритовая
// память, где считанное значение оседает в усилителях считывания на
// время восстановительной записи.
//
// Запись сквозная: после записи регистр содержит записанное значение.
// Это штатный режим read-during-write, поэтому вышестоящим блокам не
// нужно перечитывать только что записанную ячейку.
//
//----------------------------------------------------------------------
// ОГРАНИЧЕНИЕ АДРЕСНОГО ПРОСТРАНСТВА
//
// CELLS задаёт реально используемый объём. Банки, целиком лежащие выше
// него, не создаются: память данных на 30 000 ячеек занимает три банка,
// а не десять. Обращение по неиспользуемому адресу возвращает нули.
//======================================================================

`default_nettype none

//----------------------------------------------------------------------
// RamBank — банк, физическая единица памяти
//
// Внутри банка тетрады адреса сводятся в линейный индекс. В железе этой
// арифметики нет: тетрады через дешифраторы возбуждают строковые и
// столбцовые линии матрицы напрямую. Пересчёт существует только в
// поведенческой модели и в реализации для ПЛИС.
//----------------------------------------------------------------------
`ifndef SYNTH
module RamBank #(
    parameter unsigned DATA_WIDTH  = 10,
    parameter unsigned BANK_DIGITS = 2,
    parameter bit          INIT_ZERO   = 1'b1,
    parameter bit          EN_DBG_PORT = 1'b0,
    parameter unsigned ADDR_WIDTH  = BANK_DIGITS * 4
)(
    input  wire                    clk,

    input  wire [ADDR_WIDTH-1:0]   addr_i,      // BCD
    input  wire                    en_i,        // такт обращения
    input  wire                    wr_i,
    input  wire [DATA_WIDTH-1:0]   wr_data_i,
    output wire [DATA_WIDTH-1:0]   rd_data_o,

    // Второй порт чтения — только для индикации в эмуляторе
    input  wire [ADDR_WIDTH-1:0]   dbg_addr_i,
    output wire [DATA_WIDTH-1:0]   dbg_data_o
);

    localparam int unsigned CELLS = 10**BANK_DIGITS;

    // Пересчёт BCD-тетрад в линейный индекс массива
    function automatic int unsigned bcd_to_index(input logic [ADDR_WIDTH-1:0] a);
        bcd_to_index = 0;
        for (int i = int'(BANK_DIGITS) - 1; i >= 0; i--)
            bcd_to_index = bcd_to_index * 10 + int'(a[i*4 +: 4]);
    endfunction

    function automatic bit bcd_ok(input logic [ADDR_WIDTH-1:0] a);
        bcd_ok = 1'b1;
        for (int i = 0; i < int'(BANK_DIGITS); i++)
            if (a[i*4 +: 4] > 4'd9) bcd_ok = 1'b0;
    endfunction

    logic [DATA_WIDTH-1:0] mem [0:CELLS-1];

    wire                  addr_ok = bcd_ok(addr_i);
    wire [31:0]           idx_raw = bcd_to_index(addr_i);
    wire [31:0]           idx     = addr_ok ? idx_raw : 32'd0;

    logic [DATA_WIDTH-1:0] rd_q;

    // Синхронное чтение с режимом «новые данные» при записи.
    // Именно эта форма распознаётся средствами синтеза как блок памяти.
    always_ff @(posedge clk) begin
        if (en_i & addr_ok) begin
            if (wr_i) begin
                mem[idx] <= wr_data_i;
                rd_q     <= wr_data_i;      // сквозная запись
            end
            else begin
                rd_q <= mem[idx];
            end
        end
    end

    assign rd_data_o = rd_q;

    //------------------------------------------------------------------
    // Второй порт чтения
    //------------------------------------------------------------------
    generate
        if (EN_DBG_PORT) begin : g_dbg
            wire        dbg_ok  = bcd_ok(dbg_addr_i);
            wire [31:0] dbg_idx = dbg_ok ? bcd_to_index(dbg_addr_i) : 32'd0;

            logic [DATA_WIDTH-1:0] dbg_q;

            always_ff @(posedge clk) begin
                dbg_q <= dbg_ok ? mem[dbg_idx] : '0;
            end

            assign dbg_data_o = dbg_q;
        end
        else begin : g_no_dbg
            assign dbg_data_o = '0;
        end
    endgenerate

    generate
        if (INIT_ZERO) begin : g_init
            initial begin
                for (int i = 0; i < int'(CELLS); i++)
                    mem[i] = '0;
                rd_q = '0;
            end
        end
    endgenerate

endmodule


//----------------------------------------------------------------------
// RamGroup — рекурсивная группа из десяти потомков
//
// Старшая тетрада выбирает потомка, остальные уходят вниз. Потомки,
// целиком лежащие выше используемого объёма, не создаются.
//----------------------------------------------------------------------
module RamGroup #(
    parameter unsigned DATA_WIDTH  = 10,
    parameter unsigned LEVEL       = 1,    // уровней группировки над банком
    parameter unsigned BANK_DIGITS = 4,
    parameter unsigned CELLS       = 100000,
    parameter bit          INIT_ZERO   = 1'b1,
    parameter bit          EN_DBG_PORT = 1'b0,
    parameter unsigned ADDR_WIDTH  = 4 * (LEVEL + BANK_DIGITS)
)(
    input  wire                    clk,
    input  wire [ADDR_WIDTH-1:0]   addr_i,
    input  wire                    en_i,
    input  wire                    wr_i,
    input  wire [DATA_WIDTH-1:0]   wr_data_i,
    output wire [DATA_WIDTH-1:0]   rd_data_o,

    input  wire [ADDR_WIDTH-1:0]   dbg_addr_i,
    output wire [DATA_WIDTH-1:0]   dbg_data_o
);

    generate
        if (LEVEL == 0) begin : g_bank

            RamBank #(
                .DATA_WIDTH  (DATA_WIDTH),
                .BANK_DIGITS (BANK_DIGITS),
                .INIT_ZERO   (INIT_ZERO),
                .EN_DBG_PORT (EN_DBG_PORT)
            ) bank (
                .clk        (clk),
                .addr_i     (addr_i),
                .en_i       (en_i),
                .wr_i       (wr_i),
                .wr_data_i  (wr_data_i),
                .rd_data_o  (rd_data_o),
                .dbg_addr_i (dbg_addr_i),
                .dbg_data_o (dbg_data_o)
            );

        end
        else begin : g_group

            localparam int unsigned CHILD_AW    = 4 * (LEVEL - 1 + BANK_DIGITS);
            localparam int unsigned CHILD_CELLS = 10**(LEVEL - 1 + BANK_DIGITS);

            wire [3:0] digit     = addr_i    [ADDR_WIDTH-1 -: 4];
            wire [3:0] dbg_digit = dbg_addr_i[ADDR_WIDTH-1 -: 4];

            logic [DATA_WIDTH-1:0] child_rd  [0:9];
            logic [DATA_WIDTH-1:0] child_dbg [0:9];

            // Какой потомок был выбран в предыдущем такте: чтение
            // синхронное, поэтому данные приходят с задержкой на такт
            logic [3:0] digit_q, dbg_digit_q;

            always_ff @(posedge clk) begin
                if (en_i) digit_q <= digit;
                dbg_digit_q <= dbg_digit;
            end

            genvar i;
            for (i = 0; i < 10; i++) begin : child

                // Потомки выше используемого объёма не создаются
                localparam bit CHILD_USED = (i * int'(CHILD_CELLS)) < int'(CELLS);

                if (CHILD_USED) begin : g_used

                    localparam int unsigned CHILD_LEFT =
                        (int'(CELLS) - i*int'(CHILD_CELLS) > int'(CHILD_CELLS))
                        ? CHILD_CELLS
                        : (int'(CELLS) - i*int'(CHILD_CELLS));

                    wire child_en = en_i & (digit == 4'(i));

                    RamGroup #(
                        .DATA_WIDTH  (DATA_WIDTH),
                        .LEVEL       (LEVEL - 1),
                        .BANK_DIGITS (BANK_DIGITS),
                        .CELLS       (CHILD_LEFT),
                        .INIT_ZERO   (INIT_ZERO),
                        .EN_DBG_PORT (EN_DBG_PORT)
                    ) grp (
                        .clk        (clk),
                        .addr_i     (addr_i[CHILD_AW-1:0]),
                        .en_i       (child_en),
                        .wr_i       (wr_i),
                        .wr_data_i  (wr_data_i),
                        .rd_data_o  (child_rd[i]),
                        .dbg_addr_i (dbg_addr_i[CHILD_AW-1:0]),
                        .dbg_data_o (child_dbg[i])
                    );
                end
                else begin : g_unused
                    assign child_rd [i] = '0;
                    assign child_dbg[i] = '0;
                end
            end

            // Выбор потомка по тетраде предыдущего такта
            assign rd_data_o  = child_rd [digit_q];
            assign dbg_data_o = child_dbg[dbg_digit_q];
        end
    endgenerate

endmodule


//----------------------------------------------------------------------
// Ram — обёртка с интерфейсом Valid/Ready
//----------------------------------------------------------------------
module Ram #(
    parameter unsigned D_NUM         = 5'd5,      // декатронов адреса
    parameter unsigned DATA_WIDTH    = 10,
    parameter unsigned BANK_DIGITS   = 4,      // 2 — физическая модель, 4 — ПЛИС
    parameter unsigned CELLS         = 10**D_NUM,
    parameter unsigned READ_CYCLES   = 1,
    parameter unsigned WRITE_CYCLES  = 1,
    parameter bit          INIT_ZERO     = 1'b1,
    parameter bit          EN_DBG_PORT   = 1'b0,
    parameter bit          EN_OVERLAY    = 1'b0,
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

    output wire  [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_valid,
    output logic                    err,

    // Наложение ПЗУ
/* verilator lint_off UNUSEDSIGNAL */
    input  wire                     ovl_hit,
    input  wire [DATA_WIDTH-1:0]    ovl_data,
/* verilator lint_on UNUSEDSIGNAL */

    // Второй порт чтения — только эмулятор
    input  wire [ADDR_WIDTH-1:0]    dbg_addr,
    output wire [DATA_WIDTH-1:0]    dbg_data
);

    localparam int unsigned CNT_W = 8;

    logic             busy;
    logic [CNT_W-1:0] cnt;
    logic             wr_q;
    logic             err_q;
    logic             ovl_hit_q;
    logic [DATA_WIDTH-1:0] ovl_data_q;

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

    wire ovl_active = EN_OVERLAY & ovl_hit;
    wire req_err    = bcd_err | (wr & ovl_active);

    // Банк захватывает данные по фронту такта приёма, поэтому адрес
    // берётся живой, а не защёлкнутый
    wire bank_en = accept & ~req_err & ~ovl_active;

    wire [CNT_W-1:0] target = wr ? CNT_W'(WRITE_CYCLES) : CNT_W'(READ_CYCLES);

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            busy       <= 1'b0;
            cnt        <= '0;
            wr_q       <= 1'b0;
            err_q      <= 1'b0;
            ovl_hit_q  <= 1'b0;
            ovl_data_q <= '0;
            rd_valid   <= 1'b0;
            err        <= 1'b0;
        end
        else if (~busy) begin
            if (accept) begin
                busy       <= 1'b1;
                cnt        <= CNT_W'(1);
                wr_q       <= wr;
                err_q      <= req_err;
                ovl_hit_q  <= ovl_active;
                ovl_data_q <= ovl_data;
                rd_valid   <= 1'b0;
                err        <= 1'b0;
            end
        end
        else begin
            // Синхронное чтение добавляет такт: данные банка появляются
            // по фронту, следующему за тактом приёма
            if (cnt >= (wr_q ? CNT_W'(WRITE_CYCLES) : CNT_W'(READ_CYCLES))) begin
                busy     <= 1'b0;
                cnt      <= '0;
                err      <= err_q;
                rd_valid <= ~err_q;
            end
            else begin
                cnt <= cnt + CNT_W'(1);
            end
        end
    end

    //------------------------------------------------------------------
    // Дерево банков
    //------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] bank_rd;

    RamGroup #(
        .DATA_WIDTH  (DATA_WIDTH),
        .LEVEL       (D_NUM - BANK_DIGITS),
        .BANK_DIGITS (BANK_DIGITS),
        .CELLS       (CELLS),
        .INIT_ZERO   (INIT_ZERO),
        .EN_DBG_PORT (EN_DBG_PORT)
    ) top (
        .clk        (clk),
        .addr_i     (addr),
        .en_i       (bank_en),
        .wr_i       (wr),
        .wr_data_i  (wr_data),
        .rd_data_o  (bank_rd),
        .dbg_addr_i (dbg_addr),
        .dbg_data_o (dbg_data)
    );

    // Данные ПЗУ подменяют выход банка на время обращения
    assign rd_data = ovl_hit_q ? ovl_data_q : bank_rd;

`ifndef SYNTH
    initial begin
        if (D_NUM < BANK_DIGITS)
            $error("Ram: D_NUM (%0d) меньше BANK_DIGITS (%0d)", D_NUM, BANK_DIGITS);
        if (BANK_DIGITS < 2)
            $error("Ram: BANK_DIGITS (%0d) < 2 — минимальная матрица 10x10", BANK_DIGITS);
        if (CELLS > 10**D_NUM)
            $error("Ram: CELLS (%0d) больше адресного пространства (%0d)",
                   CELLS, 10**D_NUM);
        if (READ_CYCLES == 0 || WRITE_CYCLES == 0)
            $error("Ram: READ_CYCLES и WRITE_CYCLES должны быть >= 1");
        $display("Ram: %0d ячеек, банк 10^%0d, банков %0d, разрядность %0d",
                 CELLS, BANK_DIGITS,
                 (CELLS + 10**BANK_DIGITS - 1) / (10**BANK_DIGITS), DATA_WIDTH);
    end

`ifdef ASSERTIONS
    always @(posedge clk) begin
        if (rst_n && err)
            $error("Ram: недопустимое обращение по адресу %h", addr);

        // Адрес и признак операции не должны меняться до приёма запроса
        if (rst_n && $past(valid) && !$past(ready) && valid) begin
            if (addr != $past(addr))
                $error("Ram: addr изменился до handshake");
            if (wr != $past(wr))
                $error("Ram: wr изменился до handshake");
        end
    end
`endif
`endif

    /* verilator lint_off UNUSEDSIGNAL */
    wire [CNT_W-1:0] unused_target = target;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

`else

//----------------------------------------------------------------------
// Ram — заглушка на время синтеза
//
// Во время синтеза (yosys -define SYNTH=1) банковая память не нужна:
// цели синтеза — IpLine, ApLine, InsnDecoder — память не включают.
// Полное дерево банков убрано в `ifndef SYNTH, потому что рекурсивный
// RamGroup приводит hierarchy -check в бесконечный цикл. Здесь остаётся
// только интерфейс, чтобы IpMemory и DekatronPC по-прежнему
// собирались: выходы занулены, обращения не выполняются.
//----------------------------------------------------------------------
module Ram #(
    parameter unsigned D_NUM         = 5'd5,
    parameter unsigned DATA_WIDTH    = 10,
    parameter unsigned BANK_DIGITS   = 4,
    parameter unsigned CELLS         = 10**D_NUM,
    parameter unsigned READ_CYCLES   = 1,
    parameter unsigned WRITE_CYCLES  = 1,
    parameter bit          INIT_ZERO     = 1'b1,
    parameter bit          EN_DBG_PORT   = 1'b0,
    parameter bit          EN_OVERLAY    = 1'b0,
    parameter unsigned ADDR_WIDTH    = 4 * D_NUM
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     valid,
    output wire                     ready,
    input  wire                     wr,
    input  wire [ADDR_WIDTH-1:0]    addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    output wire [DATA_WIDTH-1:0]    rd_data,
    output wire                     rd_valid,
    output wire                     err,
    input  wire                     ovl_hit,
    input  wire [DATA_WIDTH-1:0]    ovl_data,
    input  wire [ADDR_WIDTH-1:0]    dbg_addr,
    output wire [DATA_WIDTH-1:0]    dbg_data
);
    assign ready    = 1'b1;
    assign rd_data  = '0;
    assign rd_valid = 1'b0;
    assign err      = 1'b0;
    assign dbg_data = '0;
endmodule

`endif

`default_nettype wire
