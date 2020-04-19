module CounterLoop(Step, Reverse, Rst_n, Out, Overflow);
	
	parameter binaryWidth = 10;//Internal dekatron width
	
	input wire Step;
	input wire Reverse;
	input wire Rst_n;
	input wire [7:0] Out;//8-4-2-1  x2
	output reg Overflow;//Set to 1 if we reach the top

	//Binary Dekatron outputs:
	wire [9:0] Out1;
	wire [9:0] Out10;

	//convert binary to 8-4-2-1
	BinToDbc bdc1(.In(Out1), .Out(Out[3:0]));
	BinToDbc bdc10(.In(Out10), .Out(Out[7:4]));

	//If we reach limits next step cause SET event
	wire upLimit = Out10[9] & Out1[9] & ~Reverse;
	wire downLimit= Out10[0] & Out1[0] & Reverse;

	//Carry step signals to next digits
	wire Enable1 = 1'b1;
	wire Enable10 = Enable1 & ((Out1[0] & Reverse ) | (Out1[9] & ~Reverse));
	
	Dekatron  dataDek1(.Step(Step), .Enable(Enable1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out1));
	Dekatron  dataDek10(.Step(Step), .Enable(Enable10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out10));
	
always @(posedge Step or negedge Rst_n)
	if (~Rst_n)
		Overflow <= 1'b0;
	else if (upLimit | downLimit)
		Overflow <= 1'b1;

endmodule