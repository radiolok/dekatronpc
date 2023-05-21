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

wire _Request;

Impulse #(.EDGE(1'b1)) reqPulse(
	.Rst_n(Rst_n),
	.Clk(Clk),
	.En(Request),
	.Impulse(_Request)
);

wire [D_NUM-1:0] Zeroes;
/* verilator lint_off UNUSEDSIGNAL */
wire [D_NUM-1:0] TopOut;
/* verilator lint_on UNUSEDSIGNAL */
wire [D_NUM-1:0] DekatronBusy;

assign Zero = &Zeroes;

wire [WIDTH-1:0] DataToDeks;

parameter [2:0] 
		IDLE = 3'b000,
		INC = 3'b010,
		DEC = 3'b011,
		SET_ZERO = 3'b101,
		SET_TOP = 3'b110,
		SET = 3'b111;
//state[2] - SET

reg [2:0] state, next;

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) state <= 0;
	else state <= next;
end

wire SetTop = Zero & Dec;
wire SetZero = &TopOut & ~Dec;
wire SetAny;

if (WRITE & (TOP_LIMIT_MODE > 0)) begin
	assign SetAny = Set | SetTop | SetZero;
	assign DataToDeks = (state == SET) ? In : 
						(state == SET_TOP) ? TOP_VALUE : 
						(state == SET_ZERO) ? {WIDTH{1'b0}} : In;
end
else begin
	assign SetAny = Set;
	assign DataToDeks = In;
end

always_comb begin
	case(state)
		IDLE: begin
			if (_Request & ~SetAny) begin
				if (Dec)
					next = DEC;
				else
					next = INC;
			end
			else if (_Request & Set) next = SET;
			else if (_Request & TOP_LIMIT_MODE & SetTop) next = SET_TOP;
			else if (_Request & TOP_LIMIT_MODE & SetZero) next = SET_ZERO;
			else next = IDLE;
		end
		default:
			next = IDLE;
	endcase
end

assign Ready = ~Request & ~(|DekatronBusy) & (state == IDLE);

wire PulseR = (state == DEC);
wire PulseF = (state == INC);
wire [1:0] Pulses;

Impulse #(.EDGE(0)
)pulsesImpDec(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.En(PulseR),
		.Impulse(Pulses[1])
	);

Impulse #(.EDGE(0)
	)pulsesImpInc(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.En(PulseF),
		.Impulse(Pulses[0])
	);
//wire [1:0] Pulses = {(state == DEC) & Clk , (state == INC) & Clk};

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
		.Set(state[2]),
		.PulseR(pulses[1]),
		.PulseF(pulses[0]),
		.In(DataToDeks[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Out(Out[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Zero(Zeroes[d]),
		.TopPin(TopOut[d]),
		.CarryLow(CarryLow),
		.CarryHigh(CarryHigh),
		.Busy(DekatronBusy[d])
	);

	assign npulses = ((CarryHigh & (state == INC)) | (CarryLow & (state == DEC))) ? 
						pulses : 2'b0;
end

endmodule
