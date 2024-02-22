module DekatronCarrySignal(
    input wire [9:0] In,
    output wire CarryLow,
    output wire CarryHigh
); 
/*This module generates carry signal for full 10-position width dekatron*/

// synopsys translate_off
wire carryLowSet = In[0];
wire noCarrySet = |In[8:1];
wire carryHighSet = In[9];

wire carryLowRst = carryHighSet | noCarrySet;
wire carryHighRst = carryLowSet | noCarrySet;

RsLatch carryLowLatch(
	.S(carryLowSet),
	.R(carryLowRst),
	.Q(CarryLow)
);
 
RsLatch carryHighLatch(
	.S(carryHighSet),
	.R(carryHighRst),
	.Q(CarryHigh)
);
// synopsys translate_on

endmodule
