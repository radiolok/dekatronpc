module DekatronCounter #(
	parameter D_NUM = 6,
	parameter D_WIDTH = 4, 
	parameter WIDTH=D_NUM*D_WIDTH
)(
	input wire Rst_n,
	input wire Clk,

	//highSpeed Clock to emulate delay of dekatron circuits. Clk is hsClk/10
	input wire hsClk,

	// All changes start on Request
    //If Set == 1, Out <= In
    //If Dec = 1, Out <= Out-1
    //Else, Out <= Out + 1
	input wire Request,
    input wire Dec,
    input wire Set,

    input wire [WIDTH-1:0] In,

    output wire Ready,
    output wire Zero,
	output reg [WIDTH-1:0] Out
);

genvar d;

wire [D_NUM-1:0] Zeroes;

assign Zero = & Zeroes;

wire [1:0] Pulses;

assign Ready = ~Request & ~(&Pulses) & ((|Out) | Zero) ;

DekatronPulseSender pulseSender(
	.Clk(Clk),
	.hsClk(hsClk),
	.Rst_n(Rst_n),
	.En(Busy),
	.Dec(Dec),
	.PulsesOut(Pulses)
);

for (d = 0; d < D_NUM; d++) begin: dek
	wire CarryLow;
	wire CarryHigh;
	wire [1:0] pulses;
	/* verilator lint_off UNUSEDSIGNAL */
	wire [1:0] npulses;
	/* verilator lint_off UNUSEDSIGNAL */
	if (d == 0) begin
		assign pulses = Pulses;
	end
	else begin
		assign pulses = dek[d-1].npulses;
	end
	DekatronModule dModule (
		.Rst_n(Rst_n),
		.hsClk(hsClk),
		.Set(Set),
		.Pulse(pulses),
		.In(In[D_WIDTH*(d+1)-1:D_WIDTH*d]),
		.Out(Out[D_WIDTH*(d+1)-1:D_WIDTH*d]),
		.Zero(Zeroes[d]),
		.CarryLow(CarryLow),
		.CarryHigh(CarryHigh)
	);

	assign npulses = ((CarryHigh & !Dec) | (CarryLow & Dec)) ? pulses : 2'b0;
end
/* verilator lint_off UNOPTFLAT */
reg Busy;
/* verilator lint_on UNOPTFLAT */

always_latch begin
    if (Request) Busy = 1'b1;
    if (Ready) Busy = 1'b0;
end


endmodule
