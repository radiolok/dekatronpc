`include "parameters.sv"

module DekatronCounter #(
	parameter D_NUM = 1,
	parameter WIDTH = D_NUM * DEKATRON_WIDTH,
	parameter READ = 1'b1,
    parameter WRITE = 1'b1
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
wire [D_NUM-1:0] Busy;

assign Zero = & Zeroes;

wire [1:0] Pulses;

wire _Request;

Impulse impulse_addr(
	.Clk(Clk),
	.Rst_n(Rst_n),
	.En(Request),
	.Impulse(_Request)
);

assign Pulses = {_Request & Dec, _Request & !Dec};

assign Ready = ~_Request & ~Set & ~(&Pulses) & ~(|Busy);

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
	DekatronModule #(
		.READ(READ),
		.WRITE(WRITE)
	)dModule (
		.Rst_n(Rst_n),
		.hsClk(hsClk),
		.Set(Set),
		.PulseR(pulses[1]),
		.PulseF(pulses[0]),
		.In(In[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Out(Out[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Zero(Zeroes[d]),
		.CarryLow(CarryLow),
		.CarryHigh(CarryHigh),
		.Busy(Busy[d])
	);

	assign npulses = ((CarryHigh & !Dec) | (CarryLow & Dec)) ? pulses : 2'b0;
end

endmodule
