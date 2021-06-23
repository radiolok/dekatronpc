module Register #(
    parameter WIDTH = 8
)(
    input wire Rst_n,
    input wire En,
    input wire Cs,
    input wire [WIDTH-1:0] In,
    output reg [WIDTH-1:0] Out
);

always @(posedge En, negedge Rst_n) begin
    if (~Rst_n) Out <= {WIDTH{1'b0}};
    else if (Cs) Out <= In;
end
endmodule

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

module RegisterFileFlatOut #(
    parameter WIDTH=8,
    parameter HEIGHT=3
)(
    input wire Rst_n,
    input wire En,
    input wire [WIDTH-1:0] In,
    input wire [HEIGHT-1:0] Cs,
    output wire [(HEIGHT*WIDTH)-1 : 0] Out
);

genvar i;
generate
    for (i = 0; i < HEIGHT; i = i+1)  begin: registers
        Register #(.WIDTH(WIDTH)) regRow(
            .Rst_n(Rst_n),
            .En(En),
            .Cs(Cs[i]),
            .In(In),
            .Out(Out[(WIDTH*(i+1))-1: (WIDTH*i)])
        );
    end
endgenerate

endmodule