module CounterIp(Step, Reverse, Rst_n, Out);
	
	parameter binaryWidth = 10;//Internal dekatron width
	
	input wire Step;
	input wire Reverse;
	input wire Rst_n;
	output wire [23:0] Out;//8-4-2-1 x6

	//Binary Dekatron outputs:
	wire [9:0] Out1;
	wire [9:0] Out10;
	wire [9:0] Out100;
	wire [9:0] Out1000;
	wire [9:0] Out10000;
	wire [9:0] Out100000;

	//convert binary to 8-4-2-1
	BinToDbc bdc1(.In(Out1), .Out(Out[3:0]));
	BinToDbc bdc10(.In(Out10), .Out(Out[7:4]));
	BinToDbc bdc100(.In(Out100), .Out(Out[11:8]));
	BinToDbc bdc1000(.In(Out1000), .Out(Out[15:12]));
	BinToDbc bdc10000(.In(Out10000), .Out(Out[19:16]));
	BinToDbc bdc100000(.In(Out100000), .Out(Out[23:20]));

	//Carry step signals to next digits
	wire Enable1 = 1'b1;
	wire Enable10 =  Enable1 & ((Out1[0] & Reverse ) | (Out1[9] & ~Reverse));
	wire Enable100 = Enable10 &((Out10[0] & Reverse ) | (Out10[9] & ~Reverse));
	wire Enable1000 =  Enable100 & ((Out100[0] & Reverse ) | (Out100[9] & ~Reverse));
	wire Enable10000 = Enable1000 &((Out1000[0] & Reverse ) | (Out1000[9] & ~Reverse));
	wire Enable100000 =  Enable10000 & ((Out10000[0] & Reverse ) | (Out10000[9] & ~Reverse));

	Dekatron  dataDek1(.Step(Step), .Enable(Enable1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out1));
	Dekatron  dataDek10(.Step(Step), .Enable(Enable10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out10));
	Dekatron  dataDek100(.Step(Step), .Enable(Enable100), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out100));
	Dekatron  dataDek1000(.Step(Step), .Enable(Enable1000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out1000));
	Dekatron  dataDek10000(.Step(Step), .Enable(Enable10000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out10000));
	Dekatron  dataDek100000(.Step(Step), .Enable(Enable100000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In({binaryWidth{1'b0}}), .Out(Out100000));

endmodule