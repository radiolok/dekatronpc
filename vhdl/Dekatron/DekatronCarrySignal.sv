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

module DekatronCarrySignal(
    input wire Rst_n,
    input wire [9:0] In,
    output wire CarryLow,
    output wire CarryHigh
); 
/*This module generates carry signal for full 10-position width dekatron*/

wire carryLowSet = In[0];
wire noCarrySet = |In[8:1];
wire carryHighSet = In[9];

wire carryLowRst = carryHighSet | noCarrySet;
wire carryHighRst = carryLowSet | noCarrySet;

RsLatch carryLowLatch(
	.Rst_n(Rst_n),
	.S(carryLowSet),
	.R(carryLowRst),
	.Q(CarryLow)
);
 
RsLatch carryHighLatch(
	.Rst_n(Rst_n),
	.S(carryHighSet),
	.R(carryHighRst),
	.Q(CarryHigh)
);

endmodule


