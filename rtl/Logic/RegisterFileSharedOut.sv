module RegisterFileSharedOut #(
    parameter WIDTH=8,
    parameter HEIGHT=3
)(
    input wire Rst_n,
    input wire En,
    input wire [WIDTH-1:0] In,
    input wire [HEIGHT-1:0] Cs,
    output wire [WIDTH-1 : 0] Out
);

wire [(HEIGHT*WIDTH)-1 : 0] OutShared;

bn_select_16_1_case #(
    .DATA_WIDTH(WIDTH))
selOut(
        .y(Out),
        .sel(Cs),
        .data(OutShared)
);

RegisterFileFlatOut #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT)
) registers(
    .Rst_n(Rst_n),
    .En(En),
    .In(In),
    .Cs(Cs),
    .Out(OutShared)
);

endmodule

