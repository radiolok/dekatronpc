module Counter(Step, Reverse, Rst_n, Set, In, Out);
	
	parameter binaryWidth = 10;
	
	input wire Step;
	input wire Reverse;
	input wire Rst_n;
	input wire Set;
	input wire [9:0] In; //8-4-2-1
	input wire [9:0] Out;//8-4-2-1

	//Binary dekatron Inputs
	wire [9:0] In1;
	wire [9:0] In10;
	wire [9:0] In100;

	wire [1:0] down = 2'b00;

	// convert 8-4-2-1 to binary
	BdcToBin bin1(.In(In[3:0]), .Out(In1));
	BdcToBin bin10(.In(In[7:4]), .Out(In10));
	BdcToBin bin100(.In({down[1:0], In[9:8]}), .Out(In100));

	//Binary Dekatron outputs:
	wire [9:0] Out1;
	wire [9:0] Out10;
	wire [9:0] Out100;

	//convert binary to 8-4-2-1
	BinToDbc bdc1(.In(Out1), .Out(Out[3:0]));
	BinToDbc bdc10(.In(Out10), .Out(Out[7:4]));
	BinToDbc bdc100(.In(Out100), .Out({down[1:0], Out[9:8]}));

	//If we reach limits next step cause SET event
	wire upLimit = Out100[2] & Out10[5] & Out1[5] & ~Reverse;
	wire downLimit= Out100[0] & Out10[0] & Out1[0] & Reverse;
	wire setData = upLimit | downLimit | Set;

	//Carry step signals to next digits
	//Allow Step signal to next digit if current is on corner stage
	wire Enable1 = 1'b1;
	wire Enable10 = setData | Enable1 & ((Out1[0] & Reverse ) | (Out1[9] & ~Reverse));
	wire Enable100 = setData | Enable10 &((Out10[0] & Reverse ) | (Out10[9] & ~Reverse));

	//Assign Input set value or MAX (255) or MIN(0) values
	wire [9:0]  _In1 = Set ? In1 : ({binaryWidth{upLimit}} & 10'b0000000001 | {binaryWidth{downLimit}} & 10'b0000100000);
	wire [9:0]  _In10 = Set ? In10 : ({binaryWidth{upLimit}} & 10'b0000000001 | {binaryWidth{downLimit}} & 10'b0000100000);
	wire [9:0]  _In100 = Set ? In100 : ({binaryWidth{upLimit}} & 10'b0000000001 | {binaryWidth{downLimit}} & 10'b0000000100);
	
	Dekatron  dataDek1(.Step(Step), .Enable(Enable1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In1), .Out(Out1));
	Dekatron  dataDek10(.Step(Step), .Enable(Enable10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In10), .Out(Out10));
	Dekatron  dataDek100(.Step(Step), .Enable(Enable100), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In100), .Out(Out100));

endmodule