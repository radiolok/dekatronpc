module BinToDcd(
    input wire [9:0] In,//position
    output wire [3:0] Out//8-4-2-1
    );

    or or1 (Out[0], In[1], In[3], In[5], In[7], In[9]);
    or or2 (Out[1], In[2], In[3], In[6], In[7]);
    or or3 (Out[2], In[4], In[5], In[6], In[7]);
    or or4 (Out[3], In[8], In[9]);

endmodule

module BcdToBin(
    input wire [3:0] In,//8-4-2-1
    output wire [9:0] Out//position
);
   
always @(*)
    case (In)
        4'b0000: Out = 10'b0000000001;
        4'b0001: Out = 10'b0000000010;
        4'b0010: Out = 10'b0000000100;
        4'b0011: Out = 10'b0000001000;
        4'b0100: Out = 10'b0000010000;
        4'b0101: Out = 10'b0000100000;
        4'b0110: Out = 10'b0001000000;
        4'b0111: Out = 10'b0010000000;
        4'b1000: Out = 10'b0100000000;
        4'b1001: Out = 10'b1000000000;
        default: Out = 10'b0000000000;
    endcase
endmodule

module BcdToBinV2(
    input wire [3:0] In,//8-4-2-1
    output wire [9:0] Out//position
);

wire [3:0] In_n;

genvar i;
generate
for (i = 0; i < 4; i = i+1)  begin: not_blocks
    not (In_n[i], In[i]);
end
endgenerate

and (Out[0], In_n[0], In_n[1], In_n[2], In_n[3]);
and (Out[1], In[0],   In_n[1], In_n[2], In_n[3]);
and (Out[2], In_n[0], In[1],   In_n[2], In_n[3]);
and (Out[3], In[0],   In[1],   In_n[2], In_n[3]);
and (Out[4], In_n[0], In_n[1], In[2],   In_n[3]);
and (Out[5], In[0],   In_n[1], In[2],   In_n[3]);
and (Out[6], In_n[0], In[1],   In[2],   In_n[3]);
and (Out[7], In[0],   In[1],   In[2],   In_n[3]);
and (Out[8], In_n[0], In_n[1], In_n[2], In[3]);
and (Out[9], In[0],   In_n[1], In_n[2], In[3]);

endmodule