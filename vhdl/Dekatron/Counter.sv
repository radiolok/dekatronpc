module Counter #(
	parameter D_NUM = 6,
	parameter D_WIDTH = 4, 
	parameter WIDTH=D_NUM*D_WIDTH,

	parameter COUNT_DELAY = 3//delay in clockticks between Req and Rdy
)(
	input wire Rst_n,
	input wire Clk,

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

reg [COUNT_DELAY-1:0] delay_shifter;
reg Busy;


DekatronPulseSender pulseSender(
	.Clk(Clk),
	.Rst_n(Rst_n),
	.En(Busy),
	.Dec(Dec),
	.PulsesOut(Pulses),
	.Ready(Ready)
);

for (d = 0; d < D_NUM; d++) begin: dek
	wire CarryLow;
	wire CarryHigh;
	wire [1:0] pulses;
	wire [1:0] npulses;
	if (d == 0) begin
		assign pulses = Pulses;
	end
	else begin
		assign pulses = dek[d-1].npulses;
	end
	dekatronModule dModule (
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

always @(posedge Clk, negedge Rst_n)
    begin
       if (~Rst_n) begin
           delay_shifter <= {{(COUNT_DELAY-1){1'b0}}, 1'b1};
           Busy <= 1'b0;
       end
       else begin
           if (Busy) begin // Simulate internal logic delay.
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
               Busy <= ~delay_shifter[0];
           end
           if (~Busy & Request) begin
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
               Busy <= 1'b1;
           end
       end
    end

endmodule