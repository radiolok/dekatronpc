/*


This module includes Memory and Data Counter

*/
module DataLine(ADDRESS, CLOCK, RST, LOAD, STORE, INC, DEC, IN, OUT);

parameter ADDRESS_WIDTH=16;
parameter MAX_ADDRESS=29999;

parameter DATA_WIDTH=8;
parameter MAX_DATA=255;

input wire[ADDRESS_WIDTH-1:0] ADDRESS;

reg [DATA_WIDTH-1:0] DataLine;

input wire CLOCK;
input wire RST;

input wire LOAD;//Load data to Data Counter
input wire STORE;//Save data from Counter to RAM

input wire INC;
input wire DEC;

input wire IN;
input wire OUT;

wire WE= 1'b1;
wire OE= 1'b1;
wire CS= 1'b0;

Memory RAM(.ADDRESS(ADDRESS), 
	.DATA(DataLine), 
	.CS(CS), 
	.OE(OE), 
	.WE(WE));


wire[DATA_WIDTH-1:0] CounterData;//Counter variable

CounterLoad(.CLOCK(CLOCK),  
	.UP(INC),
	.DOWN(DEC),
	.RST(RST),
	.COUNT(CounterData),
	.LD(LOAD),
	.LD_DATA(DataLine));

always @(negedge CLOCK && RST) begin
	if (STORE) begin
		assign DataLine = CounterData;
		end
	if (OUT)begin
		$display("Symbol: %s", DataLine);
	end
end
	

endmodule
