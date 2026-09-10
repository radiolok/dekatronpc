//======================================================================
// IpMemory — память программ
//----------------------------------------------------------------------
// Тот же банковый Ram с шириной ячейки в один опкод. Начальный загрузчик
// накладывается через входы ovl_* самого Ram, поэтому отдельного
// автомата обращений здесь нет и выходной регистр остаётся один.
//
// Загрузчик занимает старшие 100 адресов — при пяти декатронах это
// 99900..99999, ровно один банк 10x10. Записи в эту область не
// выполняются и поднимают признак ошибки.
//======================================================================

`default_nettype none

module IpMemory #(
    parameter unsigned D_NUM         = 32'd5,
    parameter unsigned READ_CYCLES   = 1,
    parameter unsigned WRITE_CYCLES  = 1,
    parameter           EN_BOOTLOADER = 1'b1,
    parameter           INIT_ZERO     = 1'b1,
    parameter           EN_DBG_PORT   = 1'b0,
    parameter           EN_ASSERTIONS = 1'b1,
    parameter unsigned ADDR_WIDTH    = 4 * D_NUM
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Valid/Ready
    input  wire                     valid,
    output wire                     ready,
    input  wire                     wr,
    input  wire [ADDR_WIDTH-1:0]    addr,
    input  wire [INSN_WIDTH-1:0]    wr_data,

    output wire [INSN_WIDTH-1:0]    rd_data,
    output wire                     rd_valid,
    output wire                     err,

    // Второй порт чтения — только эмулятор
    input  wire [ADDR_WIDTH-1:0]    dbg_addr,
    output wire [INSN_WIDTH-1:0]    dbg_data,

    output wire                     is_bootloader
);

    localparam unsigned ROM_DIGITS = 2;               // банк 10x10
    localparam unsigned ROM_AW     = ROM_DIGITS * 4;
    localparam unsigned TOP_DIGITS = D_NUM - ROM_DIGITS;
    localparam unsigned TOP_AW     = TOP_DIGITS * 4;

    localparam logic [TOP_AW-1:0] TOP_ALL_NINES = {TOP_DIGITS{4'h9}};

    // Попадание в загрузчик: девятки во всех старших тетрадах
    wire is_boot     = EN_BOOTLOADER &
                       (addr    [ADDR_WIDTH-1 -: TOP_AW] == TOP_ALL_NINES);
    wire is_boot_dbg = EN_BOOTLOADER &
                       (dbg_addr[ADDR_WIDTH-1 -: TOP_AW] == TOP_ALL_NINES);

    assign is_bootloader = is_boot;

    //------------------------------------------------------------------
    // ПЗУ загрузчика
    //------------------------------------------------------------------
    wire [INSN_WIDTH-1:0] rom_data;
    wire [INSN_WIDTH-1:0] rom_data_dbg;

    generate
        if (EN_BOOTLOADER) begin : g_boot

            bootloader #(
                .portSize (ROM_AW)
            ) storage (
                .Address (addr[ROM_AW-1:0]),
                .Data    (rom_data)
            );

            if (EN_DBG_PORT) begin : g_boot_dbg
                bootloader #(
                    .portSize (ROM_AW)
                ) storage_dbg (
                    .Address (dbg_addr[ROM_AW-1:0]),
                    .Data    (rom_data_dbg)
                );
            end
            else begin : g_no_boot_dbg
                assign rom_data_dbg = '0;
            end

        end
        else begin : g_no_boot
            assign rom_data     = '0;
            assign rom_data_dbg = '0;
        end
    endgenerate

    //------------------------------------------------------------------
    // Банковая память с наложением
    //------------------------------------------------------------------
    wire [INSN_WIDTH-1:0] ram_dbg;

    Ram #(
        .D_NUM         (D_NUM),
        .DATA_WIDTH    (INSN_WIDTH),
        .READ_CYCLES   (READ_CYCLES),
        .WRITE_CYCLES  (WRITE_CYCLES),
        .INIT_ZERO     (INIT_ZERO),
        .EN_DBG_PORT   (EN_DBG_PORT),
        .EN_OVERLAY    (EN_BOOTLOADER),
        .EN_ASSERTIONS (EN_ASSERTIONS)
    ) ram (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid    (valid),
        .ready    (ready),
        .wr       (wr),
        .addr     (addr),
        .wr_data  (wr_data),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),
        .err      (err),
        .ovl_hit  (is_boot),
        .ovl_data (rom_data),
        .dbg_addr (dbg_addr),
        .dbg_data (ram_dbg)
    );

    assign dbg_data = is_boot_dbg ? rom_data_dbg : ram_dbg;

`ifndef SYNTH
    initial begin
        if (D_NUM < 3)
            $error("IpMemory: D_NUM (%0d) < 3 — под загрузчик нужен отдельный старший банк", D_NUM);
        if (EN_BOOTLOADER)
            $display("IpMemory: загрузчик занимает старший банк, 100 инструкций");
    end
`endif

endmodule

`default_nettype wire
