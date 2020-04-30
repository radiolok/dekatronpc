`timescale 1 us / 1 ns
module testIpCounter ();

//Inputs to DUT are reg type
	reg clk = 1'b0;
	reg Rst_n = 1'b0;
	reg Reverse = 1'b0;
	wire [23:0] Out;
	

CounterIp counter(.Clk(clk),
					.Reverse(Reverse), 
					.Rst_n(Rst_n), 
					.Out(Out));


initial begin
clk = 1'b0;
forever #1 clk = ~clk;
end

//Initial Block
initial
begin
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");
	#20;
	assert( Out == 10'b10000) else $error("Forward failed %x/10", Out);
	Reverse <= 1'b1;	
	#40;
	assert( Out == 10'b1001000110) else $error("Reverse failed %x/246", Out);
	Reverse <= 1'b0;
	#2;//63
	assert( Out == 10'b0101010101) else $error("Set failed %x/155", Out);
	#199//262
	assert( Out == 10'b1001010101) else $error("CountUp failed %x/255", Out);
	#2//264
	assert( Out == 10'b0000000000) else $error("CountUp failed %x/0", Out);
	#100;
	Rst_n <= 1'b0;
	#1;
	Rst_n <= 1'b1;
	
	#100;
	$display($time, "<< Simulation Complete >>");
	$stop;
end

endmodule
