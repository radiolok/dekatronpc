(* keep_hierarchy = "yes" *) module dekatronModule(
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

BdcToBin bcdToBin(
    .In(In),
    .Out(InPos)
);

dekatron dekatronV2(
    .PulseRight(Pulse[0]),
    .PulseLeft(Pulse[1]),
    .Set(Set),
    .In(InPos),
    .Out(OutPos)
);

BinToDbc binToDbc(
    .In(OutPos),
    .Out(Out)
);

DekatronCarrySignal  dekatronCarrySignal(
    .In(OutPos),
    .CarryLow(CarryLow),
    .CarryHigh(CarryHigh)
); 

endmodule