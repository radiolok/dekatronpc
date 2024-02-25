module DekatronCounter #(
	parameter D_NUM = 3,
	parameter WIDTH = D_NUM * DEKATRON_WIDTH,
	parameter READ = 1'b1,
    parameter WRITE = 1'b1,
	parameter TOP_LIMIT_MODE = 1'b0,
	/* verilator lint_off WIDTHEXPAND */
	parameter [WIDTH-1:0] TOP_VALUE  = {4'd5, 4'd5, 4'd5}
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
	input wire SetZero,

    input wire [WIDTH-1:0] In,

    output wire Ready,
    output wire Zero,
	output wire [WIDTH-1:0] Out
);

wire _Request;

Impulse reqPulse(
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

localparam [2:0] 
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

wire SetTop;
wire SetZeroInt;
wire SetAny;

generate
if (TOP_LIMIT_MODE > 0) begin
	assign SetTop = Zero & Dec;
	assign SetZeroInt = (&TopOut & ~Dec);
end
else begin
	assign SetTop = 1'b0;
	assign SetZeroInt = 1'b0;
end

assign SetAny = Set | SetTop | SetZeroInt | SetZero;

endgenerate

always_comb begin
	next = IDLE;
	case(state)
		IDLE: begin
			if (_Request) begin
				if (~SetAny) begin
					if (Dec)
						next = DEC;
					else
						next = INC;
				end
				else if (Set) next = SET;
				else if (SetZero) next = SET_ZERO;
				else if (TOP_LIMIT_MODE) begin
					if (SetTop) next = SET_TOP;
					else if (SetZeroInt) next = SET_ZERO;
					else next = IDLE;
				end
				else next = IDLE;
			end
		end
		SET_TOP: begin
			if ( writed_n)
				next = SET_TOP;
		end
		SET_ZERO: begin
			if (writed_n)
				next = SET_ZERO;
		end
		SET: begin
			if (writed_n)
				next = SET;
		end
		default:
			next = IDLE;
	endcase
end

assign Ready = ~Request & ~(|DekatronBusy) & (state == IDLE);

wire PulseR = (state == DEC);
wire PulseF = (state == INC);
wire [1:0] Pulses;
Impulse pulsesImpDec(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.En(PulseR),
		.Impulse(Pulses[1])
	);

Impulse pulsesImpInc(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.En(PulseF),
		.Impulse(Pulses[0])
	);

wire write_set;
Impulse writeimpulse(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.En(state[2]),
		.Impulse(write_set)
	);

wire writed_n;
OneShot #(.DELAY(100)
)writeOneShot(
    .Clk(hsClk),
    .Rst_n(Rst_n),
    .En(write_set),
    .Impulse(writed_n)
);

wire [2:0] SetTopZero;

assign SetTopZero[0] = ((state == SET_ZERO) & writed_n);
assign SetTopZero[1] = ((state == SET_TOP) & writed_n);
assign SetTopZero[2] = ((state == SET) & writed_n);


generate
genvar d;
for (d = 0; d < D_NUM; d++) begin: dek
	wire CarryLow;
	wire CarryHigh;
	reg CarryLowReg;
	reg CarryHighReg;
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
		.TOP_LIMIT_MODE(TOP_LIMIT_MODE),
		.TOP_PIN_OUT(TOP_VALUE[(d+1)*DEKATRON_WIDTH-1:d*DEKATRON_WIDTH])
	)dModule (
		.Rst_n(Rst_n),
		.hsClk(hsClk),
		.Set(SetTopZero),
		.PulseR(pulses[1]),
		.PulseF(pulses[0]),
		.In(In[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Out(Out[DEKATRON_WIDTH*(d+1)-1:DEKATRON_WIDTH*d]),
		.Zero(Zeroes[d]),
		.TopPin(TopOut[d]),
		.CarryLow(CarryLow),
		.CarryHigh(CarryHigh)
	);
	assign DekatronBusy[d] = |pulses |  |SetTopZero;

	always @(posedge Clk, negedge Rst_n) begin
		if (~Rst_n) begin
			CarryLowReg <= 1'b0;
			CarryHighReg <= 1'b0;
		end
		else begin
			CarryLowReg <= CarryLow;
			CarryHighReg <= CarryHigh;
		end
	end

	assign npulses = ((CarryHighReg & (state == INC)) | (CarryLowReg & (state == DEC))) ? 
						pulses : 2'b0;
end
endgenerate

endmodule
