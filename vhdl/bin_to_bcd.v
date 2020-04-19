module BinToDbc(In, Out);

    input wire [9:0] In;
    output wire [3:0] Out;//8-4-2-1

    assign Out[0] = In[1] | In[3] | In[5] | In[7] | In[9];
    assign Out[1] = In[2] | In[3] | In[6] | In[7];
    assign Out[2] = In[4] | In[5] | In[6] | In[7];
    assign Out[3] = In[4] | In[9];

endmodule

module BdcToBin(In, Out);
    input [3:0] In;//8-4-2-1
    output wire [9:0] Out;

    assign Out[0] = ~In[3] & ~In[2] & ~In[1] & ~In[0];
    assign Out[1] = ~In[3] & ~In[2] & ~In[1] & In[0];
    assign Out[2] = ~In[3] & ~In[2] & In[1] & ~In[0];
    assign Out[3] = ~In[3] & ~In[2] & In[1] & In[0];
    assign Out[4] = ~In[3] & In[2] & ~In[1] & ~In[0];
    assign Out[5] = ~In[3] & In[2] & ~In[1] & In[0];
    assign Out[6] = ~In[3] & In[2] & In[1] & ~In[0];
    assign Out[7] = ~In[3] & In[2] & In[1] & In[0];
    assign Out[8] = In[3] & ~In[2] & ~In[1] & ~In[0];
    assign Out[9] = In[3] & ~In[2] & ~In[1] & In[0];

endmodule