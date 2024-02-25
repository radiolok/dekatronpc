(* keep_hierarchy = "yes" *) module DekatronModule #(
    parameter READ = 1'b1,
    parameter WRITE = 1'd1,
    parameter TOP_LIMIT_MODE=1'd1,
    parameter TOP_PIN_OUT = 4'd9
)(
    input wire Rst_n,
    input wire hsClk,
/* verilator lint_off UNUSEDSIGNAL */
    input wire[3:0] In,
    input wire [2:0] Set,//{Set, SetTop, SetZero}
/* verilator lint_on UNUSEDSIGNAL */
    input wire PulseF,
    input wire PulseR,
/* verilator lint_off UNDRIVEN */
    output wire[3:0] Out,
/* verilator lint_on UNDRIVEN */
    output wire Zero,
    output wire TopPin,
    output wire CarryLow,
    output wire CarryHigh
);

wire[9:0] OutPos;
wire[9:0] _OutPos;
wire[9:0] InPosDek_n;
assign Zero = OutPos[0];

generate
    genvar idx;
if (WRITE == 1) begin : Writing
    wire [9:0] InPos;
    BcdToBin_n bcdToBin(
        .In(In),
        .Out_n(InPos)
    );
    for (idx = 0; idx < 10; idx += 1) begin
        if (idx == 0)
            assign InPosDek_n[idx] = ~((Set[2] & ~InPos[idx]) | Set[0]);
        else if ((TOP_LIMIT_MODE == 1) & (idx == TOP_PIN_OUT))
            assign InPosDek_n[idx] = ~((Set[2] & ~InPos[idx]) | Set[1]);
        else
            assign InPosDek_n[idx] = ~(Set[2] & ~InPos[idx]);
    end
end
else begin
    for (idx = 0; idx < 10; idx += 1) begin
        if (idx == 0)
            assign InPosDek_n[idx] = ~Set[0];
        else if ((TOP_LIMIT_MODE == 1) & (idx == TOP_PIN_OUT))
            assign InPosDek_n[idx] = ~Set[1];
        else
            assign InPosDek_n[idx] = 1'b1;
    end
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
    .Out(_OutPos)
);

assign OutPos = (~(|_OutPos) | (|Pulses)) ? 10'bx : _OutPos;
generate
if (READ == 1) begin : Reading
    BinToBcd binToDbc(
        .In(OutPos),
        .Out(Out)
    );
    if (WRITE == 1) begin : Equalty
    /* verilator lint_off UNUSEDSIGNAL */
        wire Equal;
    /* verilator lint_on UNUSEDSIGNAL */
        Compare compare(
            .a(Out),
            .b(In),
            .eq(Equal)
        );
    end
end
endgenerate

assign CarryLow = OutPos[0];
assign CarryHigh = OutPos[9];

endmodule
