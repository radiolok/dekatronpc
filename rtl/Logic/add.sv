module add #(
    WIDTH = 3
)(
    input wire ci,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] y,
    output wire co
);

assign {co, y} = a + b + ci;

endmodule