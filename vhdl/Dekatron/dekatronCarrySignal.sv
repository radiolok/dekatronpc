module DekatronCarrySignal(
    input wire Rst_n,
    input wire [9:0] In,
    output reg CarryLow,
    output reg CarryHigh
); 
/*This module generates carry signal for full 10-position widh dekatron*/

wire carryLowPin = In[0];
wire noCarryPin = |In[1:8];
wire carryHighPin = In[9];

always_latch begin
    CarryLow <= Rst_n ? carryLowPin ? 1'b1 : (noCarryPin | carryHighPin) ? 1'b0 : CarryLow : 1'b0;
    CarryHigh <= Rst_n ? carryHighPin ? 1'b1 : (noCarryPin | carryLowPin) ? 1'b0 : CarryHigh : 1'b0;
end
 
endmodule


