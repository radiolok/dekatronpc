`timescale 100 ns / 100 ps

module ApLine_tb (
);
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #1 hsClk = ~hsClk;
end
parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);
wire DataZero;
wire ApZero;

reg ApRequest = 1'b0;
reg DataRequest = 1'b0;

wire Ready;

wire [3:0] Insn;

wire [5*4-1:0] Address;
wire [3*4-1:0] Data;

reg Dec;

ApLine  apLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .DataZero(DataZero),
    .ApZero(ApZero),
    .ApRequest(ApRequest),
    .DataRequest(DataRequest),
    .Dec(Dec),
    .Ready(Ready),
    .Address(Address),
    .Data(Data)
);

initial begin $dumpfile("ApLine_tb.vcd"); $dumpvars(0,ApLine_tb); end

reg [31:0] CLOCK_TICK;

parameter MAX_TICK = 31'd10000;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end
   else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > MAX_TICK)
      $fatal;
   end
end
initial begin 
Rst_n <= 0;
Dec <= 0;
#5 
Rst_n <= 1;

Dec <= 1'b0;
//Addr = 0, Result Data + 15
for (integer i = 0; i < 15; i++) begin

  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge Ready)
  DataRequest <= 0;
end

//Addr = 10
for (integer i = 0; i < 10; i++) begin

  repeat(1) @(posedge Clk)
  ApRequest <= 1;
  repeat(1) @(posedge Clk)
  ApRequest <= 0;
  repeat(1) @(posedge Ready)
  ApRequest <= 0;
end

//Addr 10 - Data + 17
for (integer i = 0; i < 17; i++) begin

  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge Ready)
  DataRequest <= 0;
end

Dec <= 1'b1;
//Addr 0 
for (integer i = 0; i < 10; i++) begin

  repeat(1) @(posedge Clk)
  ApRequest <= 1;
  repeat(1) @(posedge Clk)
  ApRequest <= 0;
  repeat(1) @(posedge Ready)
  ApRequest <= 0;
end

//Data -15 - Must be 0
for (integer i = 0; i < 15; i++) begin

  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge Ready)
  DataRequest <= 0;
end

$finish;

end

endmodule
