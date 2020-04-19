/*Counter module with Load function*/
module  CounterLoad(CLOCK, UP, DOWN, RST, COUNT, LD, LD_DATA);

parameter WIDTH=8;
parameter MAX_VALUE = 255;

input wire CLOCK;
input wire UP;
input wire DOWN;
input wire RST;
output reg[WIDTH-1:0] COUNT = 0;
input wire LD;
input wire LD_DATA;

always @(negedge CLOCK && LD && RST)	begin
	COUNT = LD_DATA;
	if (COUNT > MAX_VALUE)
		COUNT = MAX_VALUE;
end

always @(negedge CLOCK && UP && RST)
	if (COUNT == MAX_VALUE)
		COUNT = 0;
	else
		COUNT = COUNT + 1;

always @(negedge CLOCK && DOWN && RST)
	if (COUNT == 0)
		COUNT = MAX_VALUE;
	else
		COUNT = COUNT - 1;

always @(!RST)
	COUNT = 0;

endmodule
