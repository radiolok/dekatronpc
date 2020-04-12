module  Counter(STEP, DIR, RST, COUNT);

parameter WIDTH=8;
parameter MAX_VALUE = 255;

input wire STEP;
input wire DIR;//1 for reverse
input wire RST;
output reg[WIDTH-1:0] COUNT = 0;

always @(posedge STEP)
	if (!RST)
		COUNT <= 0;
	else begin
		if (!DIR) 
			if (COUNT == MAX_VALUE)
				COUNT <= 0;
			else
				COUNT = COUNT + 1;
		else
			if (COUNT == 0)
				COUNT = MAX_VALUE;
			else
				COUNT = COUNT - 1;
	end

endmodule
