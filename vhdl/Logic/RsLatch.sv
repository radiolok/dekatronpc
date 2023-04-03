module RsLatch(
    input wire Rst_n,
    input wire S,
    input wire R,
    output reg Q
);

always_latch begin
    if (~Rst_n)
	Q = 1'b0;
    else
        if (S)
	    Q = 1'b1;
        if (R)
	    Q = 1'b0;
end
endmodule
