module Dekatron(Step, Enable, Reverse, Rst_n, Set, In, Out);
    //Each Step cause +1 or -1(if Reverse) or storing In value(if Set)
    input wire Step;
	input wire Enable;
    input wire Reverse;//1 for reverse
    input wire Rst_n;
    input wire Set;
    input wire [9:0] In; 
    output wire[9:0] Out;

always @(posedge Step or negedge Rst_n)
	if (~Rst_n) Out <= 10'b0000000001;//Rst_n
	else if (Enable)
		if (Set) 
			Out <= In;
		else
			if (Reverse)
				Out <= {Out[0], Out[9:1]};//Enable reverse
			else
				Out <= {Out[8:0], Out[9]};//Enable forward
		    
endmodule

		
		