module DekatronCarrySignal(
	input wire en,
    input wire [9:0] In,
    output wire CarryLow,
    output wire CarryHigh
); 
/*This module generates carry signal for full 10-position width dekatron*/

`ifndef SYNTH
wire carryLowSet = In[0];
wire noCarrySet = |In[8:1];
wire carryHighSet = In[9];

/* verilator lint_off UNUSEDSIGNAL */
wire Q_n;
/* verilator lint_on UNUSEDSIGNAL */
Rs3Latch_en dekCarryLatch(
    .Sa(carryLowSet),
    .Sb(carryHighSet),
    .R(noCarrySet),
	.en(en),
    .Qa(CarryLow),
    .Qb(CarryHigh),
    .Q_n(Q_n)
);

`endif

endmodule
