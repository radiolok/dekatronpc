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
/* verilator lint_off UNDRIVEN */
wire[3:0] _Out;
/* verilator lint_on UNDRIVEN */
wire writed_n;
assign Out = Busy ? 4'bX : _Out;
wire[9:0] InPosDek;
assign Zero = OutPos[0];

generate
if (WRITE == 1) begin
    wire [9:0] InPos;
    BcdToBin bcdToBin(
        .In(In),
        .Out(InPos)
    );
    assign InPosDek = Set ? InPos : 10'b0;
end
else begin
    assign InPosDek = 10'b0;
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

OneShot #(.DELAY(100)
)oneshot(
    .Clk(hsClk),
    .Rst_n(Rst_n),
    .En(Set),
    .Impulse(writed_n)
);

Dekatron dekatron(
    .hsClk(hsClk),
    .Rst_n(Rst_n),
	.Pulses(Pulses),
    .In(InPosDek),
    .Out(OutPos)
);

generate
if (READ == 1) begin
    BinToBcd binToDbc(
        .In(OutPos),
        .Out(_Out)
    );
end
endgenerate

wire BusyDec;

DekatronCarrySignal  dekatronCarrySignal(
    .In(OutPos),
    .CarryLow(CarryLow),
    .CarryHigh(CarryHigh),
    .Busy(BusyDec)
); 

assign Busy = BusyDec | |Pulses | writed_n;

endmodule
