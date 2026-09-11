`timescale 1ns/1ps

//----------------------------------------------------------------------
// IpLine_tb — тест блока выборки инструкций (Valid/Ready, v0.7)
//
// Интерфейс DUT обновлён:
//   Rst_n/HardRst_n/Clk/hsClk        -> rst_n/soft_rst/hard_rst/clk/hs_clk
//   Request/Ready/IpAddress/...      -> valid/ready/op/ip_addr/...
//   RomRequest/RomReady/RomData      -> mem_valid/mem_ready/mem_rd_data/...
//   InsnLoading                      -> insn_loading/insn_mode/insn_in*
//
// Тестовая память программ лежит в этом же файле и загружает
// firmware.hex (генерируется из looptest.bfk скриптом emul).
// Программа: +++++++++[-+-+-]H
//----------------------------------------------------------------------

module IpLine_tb_mem #(
    parameter AW = 20
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    output wire        ready,
    input  wire        wr,
    input  wire [AW-1:0] addr,
    input  wire [3:0]  wr_data,
    output wire [3:0]  rd_data,
    output wire        rd_valid,
    output wire        err
);

    reg [3:0] mem [0:99999];

    function automatic int bcd2bin(input [AW-1:0] b);
        int r;
        r = 0;
        for (int i = 4; i >= 0; i--)
            r = r*10 + b[4*i +: 4];
        return r;
    endfunction

    localparam int unsigned IDX_W = 20;
    wire [31:0]      addr_bin = bcd2bin(addr);
    wire [IDX_W-1:0] idx      = addr_bin[IDX_W-1:0];

    initial begin
        for (int i = 0; i < 100000; i++) mem[i] = 4'h0;
        // looptest.bfk = 18 инструкций
        $readmemh("../firmware.hex", mem, 0, 16);
    end

    assign rd_data  = mem[idx];
    assign rd_valid = 1'b1;
    assign ready    = 1'b1;
    assign err      = 1'b0;

    always @(posedge clk)
        if (valid & ready & wr) mem[idx] <= wr_data;

endmodule


module IpLine_tb (
);

reg Rst_n;
reg HardRst;      // hard_rst физическая линия
reg SoftRst;
reg Clk;
reg hsClk;

initial begin
    hsClk = 1'b0;
    forever #50 hsClk = ~hsClk;
end

parameter TEST_NUM = 2000;

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

reg        ip_valid = 1'b0;
wire       ip_ready;
reg  [1:0] ip_op    = 2'd0;

wire       loop_val_zero;
wire [3:0] Insn;
wire       InsnValid;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   Address;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount;
wire       LoopOverflow;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] MemAddr;
wire [INSN_WIDTH-1:0]                     MemWrData;
wire [INSN_WIDTH-1:0]                     MemRdData;
wire       MemValid;
wire       MemReady;
wire       MemWr;
wire       MemRdValid;
wire       MemErr;

reg [11:0] Data;
assign loop_val_zero = (Data == 12'd0);

IpLine #(
    .HARD_RST_D_CNT (IP_DEKATRON_NUM - 2),
    .LOOP_READ      (1'b0)
) ipLine (
    .rst_n        (Rst_n),
    .clk          (Clk),
    .hs_clk       (hsClk),
    .soft_rst     (SoftRst),
    .hard_rst     (HardRst),
    .valid        (ip_valid),
    .ready        (ip_ready),
    .op           (ip_op),
    .loop_val_zero(loop_val_zero),
    .insn         (Insn),
    .insn_valid   (InsnValid),
    .halt_rq      (1'b0),
    .key_prev_ip  (1'b0),
    .key_next_ip  (1'b0),
    .insn_loading (1'b0),
    .insn_mode    (1'b1),
    .insn_in      (4'h0),
    .insn_in_valid(1'b0),
    .insn_in_ready(),
    .ip_addr      (Address),
    .loop_count   (LoopCount),
    .loop_overflow(LoopOverflow),
    .mem_addr     (MemAddr),
    .mem_wr_data  (MemWrData),
    .mem_rd_data  (MemRdData),
    .mem_valid    (MemValid),
    .mem_ready    (MemReady),
    .mem_wr       (MemWr),
    .mem_rd_valid (MemRdValid),
    .mem_err      (MemErr)
);

IpLine_tb_mem mem (
    .clk      (Clk),
    .rst_n    (Rst_n),
    .valid    (MemValid),
    .ready    (MemReady),
    .wr       (MemWr),
    .addr     (MemAddr),
    .wr_data  (MemWrData),
    .rd_data  (MemRdData),
    .rd_valid (MemRdValid),
    .err      (MemErr)
);

localparam [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] BOOTLOADER_ADDR =
    {4'd9, 4'd9, 4'd9, 4'd0, 4'd0};   // 99900 в BCD

initial begin $dumpfile("IpLine_tb.vcd"); $dumpvars(0, IpLine_tb); end

//----------------------------------------------------------------------
// Один запрос следующей инструкции. Возвращает retired-опкод.
//----------------------------------------------------------------------
task automatic fetch_insn(output [3:0] code);
    @(negedge Clk);
    ip_valid = 1'b1;
    ip_op    = 2'd0;               // IP_NEXT
    @(posedge Clk);
    while (!ip_ready) @(posedge Clk);
    @(negedge Clk);
    ip_valid = 1'b0;
    // Ждём возврата блока в IDLE с готовой инструкцией
    while (!(ip_ready & InsnValid)) @(posedge Clk);
    code = Insn;
    @(negedge Clk);
endtask

task automatic pulse_hard_rst();
    @(negedge Clk);
    HardRst = 1'b1;
    repeat (15) @(posedge Clk);    // 150 hs > RESET_MIN_HS = 100
    @(negedge Clk);
    HardRst = 1'b0;
    while (!ip_ready) @(posedge Clk);
    @(negedge Clk);
endtask

reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > 200000)
      $fatal(1, "Timeout");
  end
end

int  errors = 0;
reg  [3:0] code;
bit  finished = 0;

initial begin
    Rst_n   <= 1'b0;
    HardRst <= 1'b0;
    SoftRst <= 1'b0;
    ip_valid<= 1'b0;
    ip_op   <= 2'd0;
    Data    <= 12'd0;

    #2000 Rst_n <= 1'b1;
    while (!ip_ready) @(posedge Clk);

    $display("Execute looptest");
    for (int i = 0; (i < TEST_NUM) && !finished; i++) begin
        fetch_insn(code);

        case (code)
            4'h2: Data <= Data + 12'd1;   // +
            4'h3: Data <= Data - 12'd1;   // -
            4'h1: begin                   // HALT
                if (Data == 12'd0) begin
                    $display("HALT reached, Data = %0d at IP = %h",
                             Data, Address);
                    finished = 1;
                end
                else begin
                    errors++;
                    $display("FAIL: HALT with Data = %0d", Data);
                    finished = 1;
                end
            end
            default: ;                    // NOP, скобки, прочее
        endcase
    end

    if (!finished) begin
        errors++;
        $display("FAIL: program did not halt within %0d instructions", TEST_NUM);
    end

    $display("Hard reset test");
    pulse_hard_rst();
    if (Address !== BOOTLOADER_ADDR) begin
        errors++;
        $display("FAIL: hard reset address %h, expected %h",
                 Address, BOOTLOADER_ADDR);
    end
    else begin
        $display("Hard reset sets IP = %h", Address);
    end

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us IpLine Test Success!");
    if (errors) $fatal(1, "IpLine test failed");
    $finish;
end

endmodule
