`timescale 100 ns / 100 ps
module Dekatron_tb(
);
parameter WIDTH=10;
parameter TEST_NUM=20;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;

reg hsClk;
reg Clk;
reg Rst_n;

wire PulseRight;
wire PulseLeft;
reg [WIDTH-1:0] In;
wire[WIDTH-1:0] Out;

wire Ready = |Out & ~PulseLeft & ~PulseRight;
reg En;
reg Dec;
reg [9:0] data = 10'b1;

initial begin $dumpfile("dekatron_tb.vcd"); 
$dumpvars(0,Dekatron_tb); end

initial begin
    hsClk = 1'b1;
    forever #1 hsClk = ~hsClk;
end

initial begin
    In <= 10'b1;
    Rst_n <= 0;
    En <= 0;
    Dec <= 0;
    #2 
    In <= 10'b0;
    #2 Rst_n <= 1;
    $display("Count Forward\n");
    repeat(1) @(posedge Clk)
    for (integer i=0; i < test_num; i++) begin
    En <= 1 ;
    repeat(1) @(posedge Clk)
	$display("test %d: Out: %x", i, Out);
    end
    Dec <= 1;
    $display("Count Reverse\n");
    for (integer i=0; i < test_num; i++) begin
    repeat(1) @(posedge Clk)
	$display("test %d: Out: %x", i, Out);
    end
    if (Out != data) $fatal;
    $finish;
end
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);

DekatronPulseSender dekatronPulseSender(
    .Clk(Clk),
    .hsClk(hsClk),
    .Rst_n(Rst_n),
    .En(En),
    .PulsesOut({PulseRight, PulseLeft}),
    .Dec(Dec)
);

Dekatron  dek(
    .hsClk(hsClk),
    .PulseRight(PulseRight),
    .PulseLeft(PulseLeft),
    .In(In),
    .Out(Out)
);


endmodule
