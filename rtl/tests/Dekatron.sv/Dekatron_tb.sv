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
wire [WIDTH-1:0] In_n = (|In) ? ~In : {10{1'b1}};
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

reg [7:0] REF;
wire [3:0] OutBCD;

initial begin
    In <= 10'b1;
    Rst_n <= 0;
    En <= 0;
    Dec <= 0;
    REF <= 24'd0;
    #2 
    In <= 10'b0;
    #2 Rst_n <= 1;
    $display("Count Forward\n");
    repeat(1) @(posedge Clk)
    for (integer i=0; i < test_num; i++) begin
        En <= 1;
        REF <= REF + 1;
        repeat(1) @(posedge Clk)
        if (REF % 10 != OutBCD) begin
            $fatal(1, "Counter Up Failure REF: %d Out: %d", REF % 10, OutBCD);
        end
        $display("test %d: Out: %x", i, Out);
    end
    Dec <= 1;
    $display("Count Reverse\n");
    for (integer i=0; i < test_num; i++) begin
        REF <= REF - 1;
        repeat(1) @(posedge Clk)
        if (REF % 10 != OutBCD) begin
            $fatal(1, "Counter Down Failure REF: %d Out: %d", REF % 10, OutBCD);
        end
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

wire [1:0] PulsesFR = {Clk & En & Dec, Clk & En & ~Dec};
wire [1:0] PulsesRL;

DekatronPulseSender pulseSender(
	.hsClk(hsClk),
	.Rst_n(Rst_n),
	.PulseF(PulsesFR[0]),
    .PulseR(PulsesFR[1]),
	.Pulses(PulsesRL)
);

Dekatron  dek(
    .hsClk(hsClk),
    .Pulses(PulsesRL),
    .In_n(In_n),
    .Out(Out)
);



BinToBcd binToDbc(
        .In(Out),
        .Out(OutBCD)
    );


endmodule
