`include "parameters.sv"

module DekatronCounter #(
	parameter D_NUM = 3,
	parameter WIDTH = D_NUM * DEKATRON_WIDTH,
	parameter READ = 1'b1,
    parameter WRITE = 1'b1,
	parameter TOP_LIMIT_MODE = 1'b0,
	/* verilator lint_off WIDTHEXPAND */
	parameter [WIDTH-1:0] TOP_VALUE  = {4'd2, 4'd5, 4'd5}
	/* verilator lint_on WIDTHEXPAND */
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
	output wire [WIDTH-1:0] Out
);

wire [D_NUM-1:0] Zeroes;
/* verilator lint_off UNUSEDSIGNAL */
wire [D_NUM-1:0] TopOut;
/* verilator lint_on UNUSEDSIGNAL */
wire [D_NUM-1:0] DekatronBusy;

assign Zero = & Zeroes;



wire [WIDTH-1:0] _In;

wire SetAny;

reg Write = SetAny & _Request;

always @(posedge hsClk, negedge Rst_n) begin
	if (~Rst_n)
		Write <= 1'b0;
	else
		if (SetAny & _Request)
			Write <= 1'b1;
		if (~_Request)
			Write <= 1'b0;
end

if (WRITE & (TOP_LIMIT_MODE > 0)) begin
	wire Top = &TopOut;
	wire SetZero = Top & ~Dec;
	wire SetTop = Zero & Dec;
	assign SetAny = Set | SetTop | SetZero;
	assign _In = Set ? In : 
				SetTop ? TOP_VALUE : 
				SetZero ? {WIDTH{1'b0}} : In;
end
else begin
	assign SetAny = Set;
	assign _In = In;
end

wire [1:0] Pulses;

wire _Request;

Impulse impulse_addr(
	.Clk(Clk),
	.Rst_n(Rst_n),
	.En(Request),
	.Impulse(_Request)
);

wire PulsesEn = (~SetAny | ~Write) & _Request;
assign Pulses = {PulsesEn & Dec, PulsesEn & !Dec};

assign Ready = ~_Request & ~Write & ~(|DekatronBusy);

genvar d;
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
		.WRITE(WRITE),
		.TOP_PIN_OUT(TOP_VALUE[(d+1)*DEKATRON_WIDTH-1:d*DEKATRON_WIDTH])
	)dModule (
		.Rst_n(Rst_n),
		.hsClk(hsClk),
		.Set(Write),
		.PulseR(pulses[1]),
		.PulseF(pulses[0]),
		.In(_In[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Out(Out[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Zero(Zeroes[d]),
		.TopPin(TopOut[d]),
		.CarryLow(CarryLow),
		.CarryHigh(CarryHigh),
		.Busy(DekatronBusy[d])
	);

	assign npulses = ((CarryHigh & !Dec) | (CarryLow & Dec)) ? pulses : 2'b0;
end

endmodule
