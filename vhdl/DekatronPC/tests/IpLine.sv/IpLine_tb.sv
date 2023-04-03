`timescale 100 ns / 100 ps

module IpLine_tb (
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
wire dataIsZeroed;
reg Request = 1'b0;

wire Ready;

wire [3:0] Insn;

wire [6*4-1:0] Address;

IpLine  ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .dataIsZeroed(dataIsZeroed),
    .Request(Request),
    .Ready(Ready),
    .Address(Address),
    .Insn(Insn)
);
initial begin $dumpfile("IpLine_tb.vcd"); $dumpvars(0,IpLine_tb); end

reg Busy;

reg [10:0] Data;
reg [31:0] INSN_RETIRED;
assign dataIsZeroed = (Data == 0);


reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end
   else 
    CLOCK_TICK <= CLOCK_TICK + 1;
end
initial begin 
Rst_n <= 0;
Data <= 0;
Busy <= 0;

#5 
Rst_n <= 1;


for (integer i = 0; i < TEST_NUM; i++) begin

  repeat(1) @(posedge Clk)
  Request <= 1;
  repeat(1) @(posedge Clk)
  Request <= 0;
  repeat(1) @(posedge Ready)
  $display("IRET:%d Time: %d Addr: %h Insn: %b, Data: %d(%b)", i, $time, Address, Insn, Data, dataIsZeroed);
  
  case (Insn)
  4'b0010: Data <= Data + 1;
  4'b0011: Data <= Data - 1;
  4'b0001: begin $display ("CLOCKTICK: %d", CLOCK_TICK); $finish; end
  endcase

end
$fatal;

end

endmodule
