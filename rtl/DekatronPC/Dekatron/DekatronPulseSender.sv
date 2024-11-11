module DekatronPulseSender(
    //Each Step cause +1 or -1(if Dec) or storing In value(if Set)
    input wire hsClk,
    input wire Rst_n,
    input wire PulseF,
    input wire PulseR,
    output wire [1:0]Pulses
);

// This model of pulse Sender not represent real hw area consumption
wire Dec;
wire pA;
wire OS_2;
wire OS_3;
wire [1:0] _Pulses;
Impulse pulsesImpInc(
		.Clk(hsClk),
		.Rst_n(Rst_n),
		.En(PulseF),
		.Impulse(_Pulses[0])
	);
Impulse pulsesImpDec(
		.Clk(hsClk),
		.Rst_n(Rst_n),
		.En(PulseR),
		.Impulse(_Pulses[1])
	);

wire PulseAny = |_Pulses;
OneShot #(.DELAY(9)) dir( .Clk(hsClk), .Rst_n(Rst_n),  .En(PulseR), .Impulse(Dec));
OneShot #(.DELAY(4))os_1( .Clk(hsClk), .Rst_n(Rst_n),  .En(PulseAny), .Impulse(pA));
OneShot #(.DELAY(3))os_2( .Clk(hsClk), .Rst_n(Rst_n),  .En(PulseAny), .Impulse(OS_2));
OneShot #(.DELAY(8))os_3( .Clk(hsClk), .Rst_n(Rst_n),  .En(PulseAny), .Impulse(OS_3));

wire pB = OS_3 & ~OS_2;

wire PulseRight = (Dec) ? pA : pB;
wire PulseLeft = (Dec) ? pB : pA;
assign Pulses = {PulseRight, PulseLeft};

endmodule
