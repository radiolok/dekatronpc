module BcdToBinEn(In, En, Out);
    input wire [3:0] In;//8-4-2-1
    input logic  En;
    output wire [9:0] Out;//position
    logic [9:0] _Out;//position
    assign _Out[0] = ~In[3] & ~In[2] & ~In[1] & ~In[0];
    assign _Out[1] = ~In[3] & ~In[2] & ~In[1] & In[0];
    assign _Out[2] = ~In[3] & ~In[2] & In[1] & ~In[0];
    assign _Out[3] = ~In[3] & ~In[2] & In[1] & In[0];
    assign _Out[4] = ~In[3] & In[2] & ~In[1] & ~In[0];
    assign _Out[5] = ~In[3] & In[2] & ~In[1] & In[0];
    assign _Out[6] = ~In[3] & In[2] & In[1] & ~In[0];
    assign _Out[7] = ~In[3] & In[2] & In[1] & In[0];
    assign _Out[8] = In[3] & ~In[2] & ~In[1] & ~In[0];
    assign _Out[9] = In[3] & ~In[2] & ~In[1] & In[0];

    assign Out = (En) ? _Out : '0;
endmodule
