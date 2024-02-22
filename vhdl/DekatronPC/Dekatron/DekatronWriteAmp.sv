module DekatronWriteAmp(
    input wire [9:0] In,
    input wire En,
    output wire [9:0] Out_n
);

always_comb
Out_n = ~(En ? In : 10'b0);

endmodule
