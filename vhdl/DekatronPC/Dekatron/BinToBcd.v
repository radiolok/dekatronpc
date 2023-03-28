module BinToBcd(
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [9:0] In,//position
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [3:0] Out//8-4-2-1
    );

    or or1 (Out[0], In[1], In[3], In[5], In[7], In[9]);
    or or2 (Out[1], In[2], In[3], In[6], In[7]);
    or or3 (Out[2], In[4], In[5], In[6], In[7]);
    or or4 (Out[3], In[8], In[9]);

endmodule
