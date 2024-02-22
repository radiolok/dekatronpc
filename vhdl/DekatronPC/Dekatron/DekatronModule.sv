(* keep_hierarchy = "yes" *) module DekatronModule #(
    parameter READ = 1'b1,
    parameter WRITE = 1'b1,
    parameter TOP_PIN_OUT = 4'd9
)(
    input wire Rst_n,
    input wire hsClk,
/* verilator lint_off UNUSEDSIGNAL */
    input wire[3:0] In,
    input wire Set,
/* verilator lint_on UNUSEDSIGNAL */
    input wire PulseF,
    input wire PulseR,
/* verilator lint_off UNDRIVEN */
    output wire[3:0] Out,
/* verilator lint_on UNDRIVEN */
    output wire Zero,
    output wire TopPin,
    output wire CarryLow,
    output wire CarryHigh,
    output wire Busy
);

wire[9:0] OutPos;
wire[9:0] InPosDek_n;
assign Zero = OutPos[0];

generate
if (WRITE == 1) begin
    wire [9:0] InPos;
    BcdToBin bcdToBin(
        .In(In),
        .Out(InPos)
    );
    assign InPosDek_n = Set ? ~InPos : {(10){1'b1}};
end
else begin
    assign InPosDek_n = {(10){1'b1}};
end
endgenerate

wire [1:0] Pulses;

assign TopPin = OutPos[TOP_PIN_OUT];

DekatronPulseSender pulseSender(
	.hsClk(hsClk),
	.Rst_n(Rst_n),
	.PulseF(PulseF),
    .PulseR(PulseR),
	.Pulses(Pulses)
);

Dekatron dekatron(
    .hsClk(hsClk),
    .Rst_n(Rst_n),
	.Pulses(Pulses),
    .In_n(InPosDek_n),
    .Out(OutPos)
);

generate
if (READ == 1) begin
    BinToBcd binToDbc(
        .In(OutPos),
        .Out(Out)
    );
end
endgenerate

DekatronCarrySignal  dekatronCarrySignal(
    .In(OutPos),
    .CarryLow(CarryLow),
    .CarryHigh(CarryHigh)
); 

assign Busy = PulseF | PulseR | Set;

endmodule
