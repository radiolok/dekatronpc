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

wire ApLineReady;

wire [3:0] Insn;

wire [5*4-1:0] ApAddress;
wire [3*4-1:0] Data;

reg ApLineDec;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataIn;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataOut;
wire RamCS;
wire RamWE;

RAM #(
    .ROWS(170393),
    .DATA_WIDTH(12)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(ApAddress[17:0]),
    .In(RamDataIn),
    .Out(RamDataOut),
    .WE(RamWE),
    .CS(RamCS)
);

ApLine  apLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .DataZero(DataZero),
    .ApZero(ApZero),
    .ApRequest(ApRequest),
    .DataRequest(DataRequest),
    .Dec(ApLineDec),
    .Ready(ApLineReady),
    .Zero(1'b0),
    .Address(ApAddress),
    .RamDataIn(RamDataIn),
    .RamDataOut(RamDataOut),
    .RamCS(RamCS),
    .RamWE(RamWE),
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
      $fatal(1, "Timeout");
   end
end

reg [7:0] REFADDR;
reg [7:0] REFD0;
reg [7:0] REFD155;
initial begin 
Rst_n <= 0;
ApLineDec <= 0;
#5 
Rst_n <= 1;
REFADDR <= 0;
REFD0 <= 0;
REFD155 <= 0;

ApLineDec <= 1'b0;
//Addr = 0, Result Data + 15
for (integer i = 0; i < 155; i++) begin

  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  REFD0 <= REFD0 + 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge ApLineReady)
  DataRequest <= 0;
  if (REFD0 % 10 != Data[3:0]) begin
    $fatal(1, "Counter0 Failure REF: %d Out: %d", REFD0 % 10, Data[3:0]);
  end
  if ((REFD0/10) % 10 != Data[7:4]) begin
    $fatal(1, "Counter1 Failure REF: %d Out: %d", (REFD0/10) % 10, Data[7:4]);
  end
  if ((REFD0/100) % 10 != Data[11:8]) begin
    $fatal(1, "Counter2 Failure REF: %d Out: %d", (REFD0/100) % 10, Data[11:8]);
  end 
end
//Addr = 155
for (integer i = 0; i < 155; i++) begin
  REFADDR <= REFADDR + 1;
  repeat(1) @(posedge Clk)
  ApRequest <= 1;
  repeat(1) @(posedge Clk)
  ApRequest <= 0;
  repeat(1) @(posedge ApLineReady)
  ApRequest <= 0;
  if (REFADDR % 10 != ApAddress[3:0]) begin
    $fatal(1, "Counter0 Failure REF: %d Out: %d", REFADDR % 10, ApAddress[3:0]);
  end
  if ((REFADDR/10) % 10 != ApAddress[7:4]) begin
    $fatal(1, "Counter1 Failure REF: %d Out: %d", (REFADDR/10) % 10, ApAddress[7:4]);
  end
  if ((REFADDR/100) % 10 != ApAddress[11:8]) begin
    $fatal(1, "Counter2 Failure REF: %d Out: %d", (REFADDR/100) % 10, ApAddress[11:8]);
  end 
end
//Addr 10 - Data + 17
for (integer i = 0; i < 17; i++) begin
  REFD155 <= REFD155 + 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge ApLineReady)
  DataRequest <= 0;
  if (REFD155 % 10 != Data[3:0]) begin
    $fatal(1, "Counter0 Failure REF: %d Out: %d", REFD155 % 10, Data[3:0]);
  end
  if ((REFD155/10) % 10 != Data[7:4]) begin
    $fatal(1, "Counter1 Failure REF: %d Out: %d", (REFD155/10) % 10, Data[7:4]);
  end
  if ((REFD155/100) % 10 != Data[11:8]) begin
    $fatal(1, "Counter2 Failure REF: %d Out: %d", (REFD155/100) % 10, Data[11:8]);
  end   
end

ApLineDec <= 1'b1;
//Addr 0 
for (integer i = 0; i < 155; i++) begin

  repeat(1) @(posedge Clk)
  REFADDR <= REFADDR - 1;
  ApRequest <= 1;
  repeat(1) @(posedge Clk)
  ApRequest <= 0;
  repeat(1) @(posedge ApLineReady)
  ApRequest <= 0;
  if (REFADDR % 10 != ApAddress[3:0]) begin
    $fatal(1, "Counter0 Failure REF: %d Out: %d", REFADDR % 10, ApAddress[3:0]);
  end
  if ((REFADDR/10) % 10 != ApAddress[7:4]) begin
    $fatal(1, "Counter1 Failure REF: %d Out: %d", (REFADDR/10) % 10, ApAddress[7:4]);
  end
  if ((REFADDR/100) % 10 != ApAddress[11:8]) begin
    $fatal(1, "Counter2 Failure REF: %d Out: %d", (REFADDR/100) % 10, ApAddress[11:8]);
  end 
end

//Data -15 - Must be 0
for (integer i = 0; i < 15; i++) begin
  REFD0 <= REFD0 - 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 1;
  repeat(1) @(posedge Clk)
  DataRequest <= 0;
  repeat(1) @(posedge ApLineReady)
  DataRequest <= 0;
  if (REFD0 % 10 != Data[3:0]) begin
    $fatal(1, "Counter0 Failure REF: %d Out: %d", REFD0 % 10, Data[3:0]);
  end
  if ((REFD0/10) % 10 != Data[7:4]) begin
    $fatal(1, "Counter1 Failure REF: %d Out: %d", (REFD0/10) % 10, Data[7:4]);
  end
  if ((REFD0/100) % 10 != Data[11:8]) begin
    $fatal(1, "Counter2 Failure REF: %d Out: %d", (REFD0/100) % 10, Data[11:8]);
  end 
end

$finish;

end

endmodule
