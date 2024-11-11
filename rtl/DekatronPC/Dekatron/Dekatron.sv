module Dekatron(
    input wire hsClk,
    input wire Rst_n,
    input wire [1:0] Pulses,
    input wire [9:0] In_n,
    output wire [9:0] Out
);

`ifndef SYNTH
//Main wire state:
reg [29:0] Cathodes;

wire [9:0] In = ~In_n;//3FF if not write
wire toWrite = |In;

//Multiplexed state signals:

//Guide cathode right
wire GuideRightGlow = Cathodes[1] | Cathodes[4] | Cathodes[7] | Cathodes[10]
              | Cathodes[13] |  Cathodes[16] | Cathodes[19] | Cathodes[22]
              | Cathodes[25] | Cathodes[28];

//Guide Cathode Left
wire GuideLeftGlow = Cathodes[2] |  Cathodes[5] | Cathodes[8] | Cathodes[11]
              | Cathodes[14] |  Cathodes[17] | Cathodes[20] | Cathodes[23]
              | Cathodes[26] | Cathodes[29];

//Glow is on the one of the main cathodes:
wire CathodeGlow = Cathodes[0] |  Cathodes[3] | Cathodes[6] | Cathodes[9]
              | Cathodes[12] |  Cathodes[15] | Cathodes[18] | Cathodes[21]
              | Cathodes[24] | Cathodes[27];

//Connect cathodes to the output
assign Out[0] = Cathodes[0];
assign Out[1] = Cathodes[3];
assign Out[2] = Cathodes[6];
assign Out[3] = Cathodes[9];
assign Out[4] = Cathodes[12];
assign Out[5] = Cathodes[15];
assign Out[6] = Cathodes[18];
assign Out[7] = Cathodes[21];
assign Out[8] = Cathodes[24];
assign Out[9] = Cathodes[27];


//Internal extended InLong signal is used for Writing operation
wire [29:0] InLong = {{2'b00}, In[9], 2'b00, In[8], 
                    2'b00, In[7], 2'b00, In[6], 
                    2'b00, In[5], 2'b00, In[4], 
                    2'b00, In[3], 2'b00, In[2], 
                    2'b00, In[1], 2'b00, In[0]};

always @(posedge hsClk, negedge Rst_n)
 begin
    if (~Rst_n) begin
        Cathodes <= 30'b1;
    end
    else
        if (Pulses[0]) begin
            Cathodes <= (toWrite) ? InLong : 
                CathodeGlow ? {Cathodes[28:0], Cathodes[29]} :
                        GuideLeftGlow ? {Cathodes[0], Cathodes[29:1]} : Cathodes;
        end
        else if (Pulses[1]) begin
            Cathodes <= (toWrite) ? InLong : 
                CathodeGlow ? {Cathodes[0], Cathodes[29:1]}:
                GuideRightGlow ? {Cathodes[28:0], Cathodes[29]} : Cathodes;
        end
        else begin
            Cathodes <= (toWrite) ? InLong : GuideRightGlow ? {Cathodes[0], Cathodes[29:1]}:
            GuideLeftGlow ? {Cathodes[28:0], Cathodes[29]} : Cathodes;
        end
 end
`endif
endmodule

/* verilator lint_off DECLFILENAME */
module DekatronWr#(
    parameter TOP_WR = 1'b1,
    parameter TOP_PIN_OUT = 4'd5
)(
    input wire hsClk,
    input wire Rst_n,
    input wire [1:0] Pulses,
    input wire [TOP_WR:0] Set,
    output wire [9:0] Out
);
wire [9:0] InPosDek_n;

generate
genvar idx;
for (idx = 0; idx < 10; idx += 1) begin: posDek
    if (idx == 0) begin
        if (TOP_WR == 1) 
            assign InPosDek_n[idx] = Set[1];
        else
            assign InPosDek_n[idx] = ~Set[0];
    end
    else if ((TOP_WR == 1) & (idx == TOP_PIN_OUT)) begin
        assign InPosDek_n[idx] = Set[0];
    end
    else begin
        assign InPosDek_n[idx] = |Set;
    end
end
endgenerate

Dekatron dekatron(
    .hsClk(hsClk),
    .Rst_n(Rst_n),
	.Pulses(Pulses),
    .In_n(InPosDek_n),
    .Out(Out)
);
endmodule
/* verilator lint_on DECLFILENAME */