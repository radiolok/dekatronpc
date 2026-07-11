module BinaryToHex_wrapper(
    input wire [15:0] In,
    output wire [3:0] Out
);
    assign Out = BinaryToHex(In);
endmodule
