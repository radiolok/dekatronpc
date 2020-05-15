module AND_2(
    input wire  x1,
    input wire x2,
    output wire y
);

    assign y = x1 & x2;

endmodule

module AND_3(
    input wire  x1,
    input wire x2,
    input wire  x3,
    output wire y
);

    assign y = x1 & x2 & x3;

endmodule

module AND_4(
    input wire  x1,
    input wire x2,
    input wire  x3,
    input wire x4,
    output wire y
);

    assign y = x1 & x2 & x3 & x4;

endmodule

module NOT_1(
    input wire x,
    output wire y
);

assign y = ~x;

endmodule
