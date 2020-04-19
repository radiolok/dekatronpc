module CounterData(Step, Reverse, Rst_n, Set, In, Out);
	
	parameter binaryWidth = 10;//Internal dekatron width
	
	input logic Step;
	input logic Reverse;
	input logic Rst_n;
	input logic Set;
	input logic [11:0] In; //8-4-2-1
	input logic [11:0] Out;//8-4-2-1

	//Binary dekatron Inputs
	logic [9:0] In1;
	logic [9:0] In10;
	logic [9:0] In100;

	// convert 8-4-2-1 to binary
	BdcToBin bin1(.In(In[3:0]), .Out(In1));
	BdcToBin bin10(.In(In[7:4]), .Out(In10));
	BdcToBin bin100(.In(In[9:8]), .Out(In100));

	//Binary Dekatron outputs:
	logic [9:0] Out1;
	logic [9:0] Out10;
	logic [9:0] Out100;

	//convert binary to 8-4-2-1
	BinToDbc bdc1(.In(Out1), .Out(Out[3:0]));
	BinToDbc bdc10(.In(Out10), .Out(Out[7:4]));
	BinToDbc bdc100(.In(Out100), .Out(Out[11:8]));

	//If we reach limits next step cause SET event
	logic upLimit = Out100[2] & Out10[5] & Out1[5] & ~Reverse;
	logic downLimit = Out100[0] & Out10[0] & Out1[0] & Reverse;
	logic setData = upLimit | downLimit | Set;

	//Carry step signals to next digits
	logic Enable1 = 1'b1;
	logic Enable10 = setData | Enable1 & ((Out1[0] & Reverse ) | (Out1[9] & ~Reverse));
	logic Enable100 = setData | Enable10 &((Out10[0] & Reverse ) | (Out10[9] & ~Reverse));

	//Assign Input set value or MAX (255) or MIN(0) values
	logic [9:0]  _In1;
	logic [9:0]  _In10;
	logic [9:0]  _In100;
	
always_comb
	if (Set) begin
		_In1 <= In1;
		_In10 <= In10;
		_In100 <= In100;
		end
	else if (upLimit) begin
		_In1 <=   10'b0000000001;
		_In10 <=  10'b0000000001;
		_In100 <= 10'b0000000001;
		end
	else if (downLimit) begin
		_In1 <=   10'b0000100000;
		_In10 <=  10'b0000100000;
		_In100 <= 10'b0000000100;	
		end
	
	Dekatron  dataDek1(.Step(Step), .Enable(Enable1), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In1), .Out(Out1));
	Dekatron  dataDek10(.Step(Step), .Enable(Enable10), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In10), .Out(Out10));
	Dekatron  dataDek100(.Step(Step), .Enable(Enable100), .Reverse(Reverse), .Rst_n(Rst_n), .Set(setData), .In(_In100), .Out(Out100));

endmodule