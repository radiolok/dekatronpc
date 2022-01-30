module Sequencer(Clk, Rst_n, Out);

parameter LENGTH=16;

input wire Clk;
input wire Rst_n;

output reg[LENGTH-1:0] Out;

always @(posedge Clk, negedge Rst_n)
	Out <= ~Rst_n ?
		{{(LENGTH-1){1'b0}}, 1'b1}:
		{Out[LENGTH-2:0], Out[LENGTH-1]};
endmodule