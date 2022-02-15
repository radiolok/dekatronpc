module DekatronModule(
    input wire Clk,
    input wire Rst_n,
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

BcdToBinV2 bcdToBin(
    .In(In),
    .Out(InPos)
);

DekatronV2 dekatronV2(
    .PulseRight_n(Pulse[0]),
    .PulseLeft_n(Pulse[1]),
    .Set(Set),
    .In(InPos),
    .Out(OutPos)
);

BinToDcd binToDcd(
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