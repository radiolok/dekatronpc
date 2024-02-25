module Compare #(
    parameter WIDTH = 4
)(
    input wire [WIDTH-1:0]  a,
    input wire [WIDTH-1:0]  b,
    output wire eq
);

assign eq = (a == b);

endmodule
