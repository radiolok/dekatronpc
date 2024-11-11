module RsLatch(
    input wire S,
    input wire R,
    output reg Q
);

always_latch begin
    if (S)
    Q = 1'b1;
    if (R)
    Q = 1'b0;
end
endmodule
