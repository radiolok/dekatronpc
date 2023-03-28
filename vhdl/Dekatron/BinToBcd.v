module BinToBcd(
    input wire [9:0] In,//position
    output wire [3:0] Out//8-4-2-1
    );

    assign Out[0] = In[1] | In[3] | In[5] | In[7] | In[9];
    assign Out[1] = In[2] | In[3] | In[6] | In[7];
    assign Out[2] = In[4] | In[5] | In[6] | In[7];
    assign Out[3] = In[8] | In[9];

endmodule

    
