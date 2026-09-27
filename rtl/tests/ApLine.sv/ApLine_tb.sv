`timescale 1ns/1ps

//----------------------------------------------------------------------
// ApLine_tb — тест блока работы с данными (Valid/Ready, v0.7)
//
// Интерфейс DUT обновлён:
//   DataZero/ApZero/ApRequest/DataRequest/Dec/Ready ->
//   data_zero/ap_zero/valid/ready/op/dec/data_zero_valid/mem_lock
//   RAM (Address/In/Out/WE/CS) -> Ram (valid/ready/wr/addr/wr_data/
//                                    rd_data/rd_valid/err/ovl_*)
//
// Проверяется AP-счётчик, чтение ячейки (TEST) и шаг данных (+).
//----------------------------------------------------------------------
module ApLine_tb (
);
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #50 hsClk = ~hsClk;
end

parameter TEST_NUM = 20000;

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

reg             valid    = 1'b0;
reg  [3:0]      op       = 4'd0;
reg             dec      = 1'b0;
reg  [11:0]     rx_data  = 12'd0;

wire            ready;
wire            data_zero;
wire            data_zero_valid;
wire            ap_zero;
wire            mem_lock;
wire [11:0]     tx_data_bcd;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] MemAddr;
wire [9:0]      MemWrData;
wire [9:0]      MemRdData;
wire            MemValid;
wire            MemReady;
wire            MemWr;
wire            MemRdValid;
wire            MemErr;

localparam [3:0]
    OP_NOP       = 4'd0,
    OP_AP_STEP   = 4'd1,
    OP_AP_ZERO   = 4'd2,
    OP_DATA_STEP = 4'd3,
    OP_DATA_ZERO = 4'd4,
    OP_CIN       = 4'd5,
    OP_COUT      = 4'd6,
    OP_LOAD      = 4'd7,
    OP_STORE     = 4'd8,
    OP_CLRML     = 4'd9,
    OP_TEST      = 4'd10;

ApLine apLine (
    .rst_n          (Rst_n),
    .clk            (Clk),
    .hs_clk         (hsClk),
    .soft_rst       (1'b0),
    .hard_rst       (1'b0),
    .valid          (valid),
    .ready          (ready),
    .op             (op),
    .dec            (dec),
    .data_zero      (data_zero),
    .data_zero_valid(data_zero_valid),
    .ap_zero        (ap_zero),
    .mem_lock       (mem_lock),
    .rx_data_bcd    (rx_data),
    .tx_data_bcd    (tx_data_bcd),
    .mem_addr       (MemAddr),
    .mem_wr_data    (MemWrData),
    .mem_rd_data    (MemRdData),
    .mem_valid      (MemValid),
    .mem_ready      (MemReady),
    .mem_wr         (MemWr),
    .mem_rd_valid   (MemRdValid),
    .mem_err        (MemErr)
);

Ram #(
    .D_NUM         (AP_DEKATRON_NUM),
    .DATA_WIDTH    (10),
    .READ_CYCLES   (1),
    .WRITE_CYCLES  (1),
    .INIT_ZERO     (1'b1),
    .EN_DBG_PORT   (1'b0),
    .EN_OVERLAY    (1'b0)
) ram (
    .clk      (Clk),
    .rst_n    (Rst_n),
    .valid    (MemValid),
    .ready    (MemReady),
    .wr       (MemWr),
    .addr     (MemAddr),
    .wr_data  (MemWrData),
    .rd_data  (MemRdData),
    .rd_valid (MemRdValid),
    .err      (MemErr),
    .ovl_hit  (1'b0),
    .ovl_data (10'h0),
    .dbg_addr (20'h0),
    .dbg_data ()
);

localparam [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] AP_ZERO_BCD =
    {AP_DEKATRON_NUM{4'd0}};

function automatic [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ap_bcd(input int unsigned v);
    reg [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] r;
    int unsigned t;
    t = v;
    r = '0;
    for (int i = 0; i < AP_DEKATRON_NUM; i++) begin
        r[4*i +: 4] = t % 10;
        t = t / 10;
    end
    return r;
endfunction

function automatic [11:0] data_bcd(input int unsigned v);
    data_bcd = {4'((v/100)%10), 4'((v/10)%10), 4'(v%10)};
endfunction

initial begin $dumpfile("ApLine_tb.vcd"); $dumpvars(0, ApLine_tb); end

reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > 2000000)
      $fatal(1, "Timeout");
  end
end

//----------------------------------------------------------------------
// Одна операция по Valid/Ready
//----------------------------------------------------------------------
task automatic do_op(input [3:0] o, input bit d, input [11:0] rx);
    @(negedge Clk);
    while (!ready) @(negedge Clk);
    valid   = 1'b1;
    op      = o;
    dec     = d;
    rx_data = rx;
    @(posedge Clk);          // accept
    @(negedge Clk);
    valid = 1'b0;
    while (!ready) @(negedge Clk);
endtask

int errors = 0;

initial begin
    Rst_n   <= 1'b0;
    valid   <= 1'b0;
    op      <= OP_NOP;
    dec     <= 1'b0;
    rx_data <= 12'd0;

    #2000 Rst_n <= 1'b1;
    while (!ready) @(posedge Clk);

    $display("AP increment test");
    for (int i = 1; i <= 20; i++) begin
        do_op(OP_AP_STEP, 1'b0, 12'd0);
        if (MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", MemAddr, ap_bcd(i));
        end
    end

    $display("AP decrement test");
    for (int i = 19; i >= 0; i--) begin
        do_op(OP_AP_STEP, 1'b1, 12'd0);
        if (MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", MemAddr, ap_bcd(i));
        end
    end
    if (!ap_zero) begin
        errors++;
        $display("FAIL: ap_zero not set at AP=0");
    end

    $display("Memory TEST at AP=0");
    do_op(OP_TEST, 1'b0, 12'd0);
    if (!data_zero_valid) begin
        errors++;
        $display("FAIL: data_zero_valid not set after TEST");
    end
    if (!data_zero) begin
        errors++;
        $display("FAIL: data_zero not set for zero cell");
    end

    $display("Memory COUT at AP=0");
    do_op(OP_COUT, 1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== 12'd0) begin
        errors++;
        $display("FAIL: tx_data_bcd after COUT = %0d, expected 0", tx_data_bcd);
    end

    $display("Data step test (lazy read)");
    for (int i = 1; i <= 10; i++) begin
        do_op(OP_DATA_STEP, 1'b0, 12'd0);
        if (tx_data_bcd[11:0] !== data_bcd(i)) begin
            errors++;
            $display("FAIL: data + -> %0d, expected %0d", tx_data_bcd, i);
        end
    end
    for (int i = 9; i >= 6; i--) begin
        do_op(OP_DATA_STEP, 1'b1, 12'd0);
        if (tx_data_bcd[11:0] !== data_bcd(i)) begin
            errors++;
            $display("FAIL: data - -> %0d, expected %0d", tx_data_bcd, i);
        end
    end

    $display("AP move flushes cell, LOAD reads it back");
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP 0->1, cell0 := 6
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP 1->0, cell1 := 0
    do_op(OP_LOAD,     1'b0, 12'd0);        // Data := cell0
    if (tx_data_bcd[11:0] !== data_bcd(6)) begin
        errors++;
        $display("FAIL: LOAD -> %0d, expected 6", tx_data_bcd);
    end

    $display("DATA_ZERO test");
    do_op(OP_DATA_ZERO, 1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== 12'd0) begin
        errors++;
        $display("FAIL: DATA_ZERO -> %0d, expected 0", tx_data_bcd);
    end

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us ApLine Test Success!");
    if (errors) $fatal(1, "ApLine test failed");
    $finish;
end

endmodule
