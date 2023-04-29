`include "parameters.sv"

module DekatronPulseSender(
    //Each Step cause +1 or -1(if Dec) or storing In value(if Set)
    input wire hsClk,
    input wire Rst_n,
    input wire PulseF,
    input wire PulseR,
    output wire [1:0]Pulses
);

reg Dec;
reg En;

// This model of pulse Sender not represent real hw area consumption
reg [3:0] Cnt;

always @(posedge hsClk, negedge Rst_n) begin
	if (~Rst_n) begin
		Cnt <= 4'd0;
		Dec <= 1'b0;
		En <= 1'b0;
	end
	else begin
		if (PulseR)
			Dec <= 1'b1;
		if (PulseF)
			Dec <= 1'b0;
		if (PulseF | PulseR) begin
			En <= 1'b1;
			Cnt <= Cnt + 4'b1;
		end
		if (En) begin
			Cnt <= Cnt + 4'b1;
			if (Cnt >=8) begin
				Cnt <= 4'd0;
				En <= 1'b0;
			end
		end
	end
end
/* verilator lint_off UNUSEDSIGNAL */
wire [9:0] CntPos;
/* verilator lint_on UNUSEDSIGNAL */
BcdToBin bcdToBin(
	.In(Cnt),
	.Out(CntPos)
);

wire pA = |CntPos[3:1];
wire pB = |CntPos[6:4];

wire PulseRight = Dec? pA : pB;
wire PulseLeft = Dec? pB : pA;

assign Pulses = {PulseRight, PulseLeft};

endmodule
