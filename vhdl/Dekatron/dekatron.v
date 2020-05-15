module Dekatron(
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
		Out <= Set ? In : Reverse ? 
				{Out[0], Out[9:1]}://Enable reverse
				{Out[8:0], Out[9]};//Enable forward
endmodule

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