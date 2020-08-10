module dekatronCarrySignal(
    input wire Rst_n,
    input wire [9:0] In,
    output reg CarryLow,
    output reg CarryHigh
); 
/*This module generates carry signal for full 10-position widh dekatron*/

assign carryLowPin = In[0];
assign noCarryPin = In[1] | In[2] | In[3] | In[4] | In[5] | In[6] | In[7] | In[8];
assign carryHighPin = In[9];

always_latch begin
    if (~Rst_n) begin
        CarryLow <= 1'b0;
        CarryHigh <= 1'b0;
    end
    else
        CarryLow <= carryLowPin ? 1'b1 : (noCarryPin | carryHighPin) ? 1'b0 : CarryLow;
        CarryHigh <= carryHighPin ? 1'b1 : (noCarryPin | carryLowPin) ? 1'b0 : CarryHigh;
    end
 
endmodule


