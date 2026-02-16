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
    output wire Ready,

    input wire Dec,
    input wire Set,
	input wire SetZero,

    input wire [WIDTH-1:0] In,

    output wire Zero,
	output wire [WIDTH-1:0] Out
);

reg [D_NUM-1:0] Zeroes;
reg [D_NUM-1:0] Nines;
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
//current_state[2] - SET

reg [2:0] current_state, next_state;

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) current_state <= 0;
	else current_state <= next_state;
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
	next_state = IDLE;
	case(current_state)
		IDLE: begin
			if (Request) begin
				if (~SetAny) begin
					if (Dec)
						next_state = DEC;
					else
						next_state = INC;
				end
				else if (Set) next_state = SET;
				else if (SetZero) next_state = SET_ZERO;
				else if (TOP_LIMIT_MODE) begin
					if (SetTop) next_state = SET_TOP;
					else if (SetZeroInt) next_state = SET_ZERO;
					else next_state = IDLE;
				end
				else next_state = IDLE;
			end
		end
		SET_TOP: begin
			if ( writed_n)
				next_state = SET_TOP;
		end
		SET_ZERO: begin
			if (writed_n)
				next_state = SET_ZERO;
		end
		SET: begin
			if (writed_n)
				next_state = SET;
		end
		default:
			next_state = IDLE;
	endcase
end

assign Ready = ~(|DekatronBusy) & (current_state == IDLE);

wire PulseR = (current_state == DEC);
wire PulseF = (current_state == INC);
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
		.En(current_state[2]),
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

assign SetTopZero[0] = ((current_state == SET_ZERO) & writed_n);
assign SetTopZero[1] = ((current_state == SET_TOP) & writed_n);
assign SetTopZero[2] = ((current_state == SET) & writed_n);


generate
genvar d;
for (d = 0; d < D_NUM; d++) begin: dek
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
	wire DekZero;
	wire DekNine;
	wire Equal;
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
		.Zero(DekZero),
		.Nine(DekNine),
		.Equal(Equal),
		.TopPin(TopOut[d])
	);
	assign DekatronBusy[d] = |pulses |  |SetTopZero;

	always @(posedge Clk, negedge Rst_n) begin
		if (~Rst_n) begin
			Zeroes[d] <= 1'b0;
			Nines[d] <= 1'b0;
		end
		else begin
			Zeroes[d] <= DekZero;
			Nines[d] <= DekNine;
		end
	end

	assign npulses = ((Nines[d] & (current_state == INC)) | (Zeroes[d] & (current_state == DEC))) ?
						pulses : 2'b0;
end
endgenerate

endmodule
