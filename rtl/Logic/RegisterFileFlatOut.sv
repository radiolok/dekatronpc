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
