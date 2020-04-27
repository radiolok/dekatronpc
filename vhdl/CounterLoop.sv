module CounterLoop(Clk, Reverse, Rst_n, Zero, Ready, Overflow);
	
	parameter binaryWidth = 10;//Internal dekatron width
	
	input wire Clk;
	input wire Reverse;
	input wire Rst_n;
	output wire Zero;//Set one if at > 0
	output wire Ready;
	output reg Overflow;//Set to 1 if we reach the top

	assign Ready = 1'b1;

	//Binary Dekatron outputs:
	wire [9:0] Out1;
	wire [9:0] Out10;

	//If we reach limits next step cause SET event
	wire upLimit = Out10[9] & Out1[9] & ~Reverse;
	wire downLimit= Out10[0] & Out1[0] & Reverse;

	assign Zero = Out10[0] & Out1[0];

	//Carry step signals to next digits
	wire Enable1 = 1'b1;
	wire Enable10 = Enable1 & ((Out1[0] & Reverse ) | (Out1[9] & ~Reverse));
	
	Dekatron  dataDek1(.Step(Clk), .Enable(Enable1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out1));
	Dekatron  dataDek10(.Step(Clk), .Enable(Enable10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out10));
	
always @(posedge Clk or negedge Rst_n)
	if (~Rst_n)
		Overflow <= 1'b0;
	else if (upLimit | downLimit)
		Overflow <= 1'b1;

endmodule