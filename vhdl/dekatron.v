module Dekatron(Step, Enable, Reverse, Rst_n, Set, In, Out);
    //Each Step cause +1 or -1(if Reverse) or storing In value(if Set)
    input wire Step;
	input wire Enable;
    input wire Reverse;//1 for reverse
    input wire Rst_n;
    input wire Set;
    input wire [9:0] In; 
    output reg[9:0] Out;

wire[3:0] signals = {Rst_n, Set, Enable, Reverse};
	 
always @(posedge Step or negedge Rst_n)
	casez(signals)
		4'b0???: Out <= 10'b0000000001;//Rst_n
		4'b111?: Out <= In;//Set
		4'b1010: Out <= {Out[8:0], Out[9]};//Enable forward
		4'b1011: Out <= {Out[0], Out[9:1]};//Enable reverse
	endcase
	

    
endmodule