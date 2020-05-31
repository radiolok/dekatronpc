module Dekatron(
    //For forward direction, use PulseRight->PulseLeft order
    //and vise versa for reverse direction
    input wire PulseRight,
	input wire PulseLeft,
    input wire Rst_n,
    input wire Set,
    input wire [9:0] In,
    output wire[9:0] Out
);


//Main wire state:
reg [29:0] Cathodes;

//Multiplexed state signals:

//Guide cathode right
wire GuideRightGlow = Cathodes[1] |  Cathodes[4] | Cathodes[7] | Cathodes[10]
              | Cathodes[13] |  Cathodes[16] | Cathodes[19] | Cathodes[22]
              | Cathodes[25] | Cathodes[28];

//Guide Cathode Left
wire GuideLeftGlow = Cathodes[2] |  Cathodes[5] | Cathodes[8] | Cathodes[11]
              | Cathodes[12] |  Cathodes[17] | Cathodes[20] | Cathodes[23]
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
wire InLong[29:0];

assign InLong[0] = In[0];
assign InLone[2:1] = 2'b00;
assign InLong[3] = In[1];
assign InLone[5:4] = 2'b00;
assign InLong[6] = In[2];
assign InLone[8:7] = 2'b00;
assign InLong[9] = In[3];
assign InLone[11:10] = 2'b00;
assign InLong[12] = In[4];
assign InLone[14:13] = 2'b00;
assign InLong[15] = In[5];
assign InLone[17:16] = 2'b00;
assign InLong[18] = In[6];
assign InLone[20:19] = 2'b00;
assign InLong[21] = In[7];
assign InLone[23:22] = 2'b00;
assign InLong[24] = In[8];
assign InLone[26:25] = 2'b00;
assign InLong[27] = In[9];
assign InLone[29:28] = 2'b00;

wire PulseLeft_n = ~PulseLeft;
wire PulseRight_n = ~ PulseRight;

always @(negedge Rst_n, posedge PulseRight, posedge PulseLeft, posedge PulseRight_n, posedge PulseLeft_n)
 begin
     if (~Rst_n) begin
         Cathodes <= 30'b000000000000000000000000000001;//Rst_n
     end
     else begin
        if (CathodeGlow) begin
            if (PulseRight)
                Cathodes <= {Out[28:0], Out[29]};
            if (PulseLeft)
                Cathodes <= {Out[0], Out[29:1]};
        end//CathodeGlow
        else if (GuideRightGlow) begin
            if (PulseLeft) begin
                Cathodes <= {Out[28:0], Out[29]};
                else if (PulseRight_n)//Clean Guide Right signal but with no Guide Left:
                    Cathodes <= {Out[0], Out[29:1]};
                end
            end//GuideRightGlow
        else if (GuideLeftGlow) begin
            if (PulseRight) begin
                Cathodes <= {Out[0], Out[29:1]};
                else if (PulseLeft_n)//Clean Guide Left signal but with no Guide Left:
                    Cathodes <= {Out[28:0], Out[29]};
                end
            end//GuideRightGlow
     end//Rst_n
 end

//forward: Cathodes <= {Out[28:0], Out[29]};
//Reverse: Cathodes <= {Out[0], Out[29:1]};

module Octotron(
    //Each Step cause +1 or -1(if Reverse) or storing In value(if Set)
    input wire Step,
	input wire En,
    input wire Reverse,//1 for reverse
    input wire Rst_n,
    input wire Set,
    input wire [9:0] In,
    output reg[9:0] Out
);

always @(posedge Step, negedge Rst_n)
	if (~Rst_n) 
		Out <= 10'b0000000001;//Rst_n
	else if (En)
		Out <= Set ? {2'b00, In[7:0]} : Reverse ?
				Out[0]? 10'b0010000000 : {Out[0], Out[9:1]}://Enable reverse
				Out[7]? 10'b0000000001 : {Out[8:0], Out[9]};//Enable forward

endmodule