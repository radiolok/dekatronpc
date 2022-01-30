module BinToDbc(
    input wire [9:0] In,//position
    output wire [3:0] Out//8-4-2-1
    );

    assign Out[0] = In[1] | In[3] | In[5] | In[7] | In[9];
    assign Out[1] = In[2] | In[3] | In[6] | In[7];
    assign Out[2] = In[4] | In[5] | In[6] | In[7];
    assign Out[3] = In[8] | In[9];

endmodule

module BdcToBin(In, Out);
    input wire [3:0] In;//8-4-2-1
    output wire [9:0] Out;//position
    wire [3:0] In_n;
    NOT_1 NOT_1_0(In[0], In_n[0]);
    NOT_1 NOT_1_1(In[1], In_n[1]);
    NOT_1 NOT_1_2(In[2], In_n[2]);
    NOT_1 NOT_1_3(In[3], In_n[3]);

    AND_4 AND_4_0(In_n[0], In_n[1], In_n[2], In_n[3], Out[0]);
    AND_4 AND_4_1(In[0],   In_n[1], In_n[2], In_n[3], Out[1]);
    AND_4 AND_4_2(In_n[0], In[1],   In_n[2], In_n[3], Out[2]);
    AND_4 AND_4_3(In[0],   In[1],   In_n[2], In_n[3], Out[3]);
    AND_4 AND_4_4(In_n[0], In_n[1], In[2],   In_n[3], Out[4]);
    AND_4 AND_4_5(In[0],   In_n[1], In[2],   In_n[3], Out[5]);
    AND_4 AND_4_6(In_n[0], In[1],   In[2],   In_n[3], Out[6]);
    AND_4 AND_4_7(In[0],   In[1],   In[2],   In_n[3], Out[7]);
    AND_4 AND_4_8(In_n[0], In_n[1], In_n[2], In[3],   Out[8]);
    AND_4 AND_4_9(In[0],   In_n[1], In_n[2], In[3],   Out[9]);

endmodule

module BinToOct(
    input wire [7:0] In,//position
    output wire [2:0] Out//4-2-1
    );

    assign Out[0] = In[1] | In[3] | In[5] | In[7];
    assign Out[1] = In[2] | In[3] | In[6] | In[7];
    assign Out[2] = In[4] | In[5] | In[6] | In[7];

endmodule

module OctToBin(In, Out);
    input wire [2:0] In;//4-2-1
    output wire [7:0] Out;//position
    wire [2:0] In_n;

    NOT_1 NOT_1_0(In[0], In_n[0]);
    NOT_1 NOT_1_1(In[1], In_n[1]);
    NOT_1 NOT_1_2(In[2], In_n[2]);

    AND_3 AND_3_0(In_n[0], In_n[1], In_n[2], Out[0]);
    AND_3 AND_3_1(In[0],   In_n[1], In_n[2], Out[1]);
    AND_3 AND_3_2(In_n[0], In[1],   In_n[2], Out[2]);
    AND_3 AND_3_3(In[0],   In[1],   In_n[2], Out[3]);
    AND_3 AND_3_4(In_n[0], In_n[1], In[2],   Out[4]);
    AND_3 AND_3_5(In[0],   In_n[1], In[2],   Out[5]);
    AND_3 AND_3_6(In_n[0], In[1],   In[2],   Out[6]);
    AND_3 AND_3_7(In[0],   In[1],   In[2],   Out[7]);

endmodule