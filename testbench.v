`timescale 1 us / 100 ns
module tb ();

//Inputs to DUT are reg type
	reg CLOCK = 1'b0;
	reg RST_N = 1'b1;
	wire [15:0] OUT = 1'b1;

//Instantiate the DUT
	dekatronpc Test1 (
		.CLOCK(CLOCK),
		.OUT(OUT),
		.RST_N(RST_N)
	);

//Create a 50MHz clock
always
	#1 CLOCK = ~CLOCK;

//Initial Block
initial
begin
	$display($time, " << Starting Simulation >> ");
	CLOCK = 1'b0;
	
	
	#240;
	$display($time, "<< Simulation Complete >>");
	$stop;
end

endmodule
