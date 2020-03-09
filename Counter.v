module  Counter(UP, DOWN, RST, COUNT);

parameter WIDTH=8;
parameter MAX_VALUE = 255;

input wire UP;
input wire DOWN;
input wire RST;
output reg[WIDTH-1:0] COUNT = 0;


always @(posedge UP && RST)
	if (COUNT == MAX_VALUE)
		COUNT = 0;
	else
		COUNT = COUNT + 1;

always @(posedge DOWN && RST)
	if (COUNT == 0)
		COUNT = MAX_VALUE;
	else
		COUNT = COUNT - 1;

always @(!RST)
	COUNT = 0;

endmodule
