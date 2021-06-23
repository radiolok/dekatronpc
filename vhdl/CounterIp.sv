module CounterIp(Clk, Reverse, Rst_n, Ready, Out);
	
	input wire Clk;
	input wire Reverse;
	input wire Rst_n;
	output wire Ready;
	output wire [17:0] Out;//4-2-1 x6

	assign Ready = 1'b1;
	
	//Binary Dekatron outputs:
	wire [9:0] Out1;
	wire [9:0] Out10;
	wire [9:0] Out100;
	wire [9:0] Out1000;
	wire [9:0] Out10000;
	wire [9:0] Out100000;

	//convert binary to 8-4-2-1
	BinToOct bdc1(.In(Out1), .Out(Out[2:0]));
	BinToOct bdc10(.In(Out10), .Out(Out[5:3]));
	BinToOct bdc100(.In(Out100), .Out(Out[8:6]));
	BinToOct bdc1000(.In(Out1000), .Out(Out[11:9]));
	BinToOct bdc10000(.In(Out10000), .Out(Out[14:12]));
	BinToOct bdc100000(.In(Out100000), .Out(Out[17:15]));

	//Carry step signals to next digits
	wire En1 = 1'b1;
	wire En10 =  En1 & ((Out1[0] & Reverse ) | (Out1[7] & ~Reverse));
	wire En100 = En10 &((Out10[0] & Reverse ) | (Out10[7] & ~Reverse));
	wire En1000 =  En100 & ((Out100[0] & Reverse ) | (Out100[7] & ~Reverse));
	wire En10000 = En1000 &((Out1000[0] & Reverse ) | (Out1000[7] & ~Reverse));
	wire En100000 =  En10000 & ((Out10000[0] & Reverse ) | (Out10000[7] & ~Reverse));

	Dekatron  dataDek1(.Step(Clk), .En(En1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out1));
	Dekatron  dataDek10(.Step(Clk), .En(En10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out10));
	Dekatron  dataDek100(.Step(Clk), .En(En100), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out100));
	Dekatron  dataDek1000(.Step(Clk), .En(En1000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out1000));
	Dekatron  dataDek10000(.Step(Clk), .En(En10000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out10000));
	Dekatron  dataDek100000(.Step(Clk), .En(En100000), .Reverse(Reverse), .Rst_n(Rst_n), .Set(1'b0), .In(10'b0), .Out(Out100000));

endmodule