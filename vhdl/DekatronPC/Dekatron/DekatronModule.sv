(* keep_hierarchy = "yes" *) module DekatronModule #(
    parameter READ = 1'b1,
    parameter WRITE = 1'b1
)(
    input wire Rst_n,
    input wire hsClk,
/* verilator lint_off UNUSEDSIGNAL */
    input wire[3:0] In,
    input wire Set,
/* verilator lint_on UNUSEDSIGNAL */
    input wire[1:0] Pulse,
/* verilator lint_off UNDRIVEN */
    output wire[3:0] Out,
/* verilator lint_on UNDRIVEN */
    output wire Zero,
    output wire CarryLow,
    output wire CarryHigh
);


wire[9:0] OutPos;
wire[9:0] InPosDek;
assign Zero = OutPos[0];

if (WRITE == 1) begin
    wire [9:0] InPos;
    BcdToBin bcdToBin(
        .In(In),
        .Out(InPos)
    );
    assign InPosDek = Set? InPos : 10'b0;
end
else begin
    assign InPosDek = 10'b0;
end

Dekatron dekatronV2(
    .hsClk(hsClk),
    .Rst_n(Rst_n),
    .PulseRight(Pulse[1]),
    .PulseLeft(Pulse[0]),
    .In(InPosDek),
    .Out(OutPos)
);

if (READ == 1) begin
    BinToBcd binToDbc(
        .In(OutPos),
        .Out(Out)
    );
end

DekatronCarrySignal  dekatronCarrySignal(
    .Rst_n(Rst_n),
    .In(OutPos),
    .CarryLow(CarryLow),
    .CarryHigh(CarryHigh)
); 

endmodule
