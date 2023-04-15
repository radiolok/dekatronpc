(* keep_hierarchy = "yes" *) module DekatronModule(
    input wire Rst_n,
    input wire hsClk,
    input wire Set,
    input wire[1:0] Pulse,
    input wire[3:0] In,
    output wire[3:0] Out,
    output wire Zero,
    output wire CarryLow,
    output wire CarryHigh
);

wire [9:0] InPos;
wire[9:0] OutPos;
assign Zero = OutPos[0];

BcdToBin bcdToBin(
    .In(In),
    .Out(InPos)
);

wire[9:0] InPosDek = Set? InPos : 10'b0;

Dekatron dekatronV2(
    .hsClk(hsClk),
    .Rst_n(Rst_n),
    .PulseRight(Pulse[1]),
    .PulseLeft(Pulse[0]),
    .In(InPosDek),
    .Out(OutPos)
);

BinToBcd binToDbc(
    .In(OutPos),
    .Out(Out)
);

DekatronCarrySignal  dekatronCarrySignal(
    .Rst_n(Rst_n),
    .In(OutPos),
    .CarryLow(CarryLow),
    .CarryHigh(CarryHigh)
); 

endmodule
