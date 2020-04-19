`timescale 1 ns / 1 ps


module Sequenser(Clk, Rst, Out);

input wire Clk;
input wire Rst;

output reg[15:0] Out = 15'b1;

always @(posedge Clk, negedge Rst)
	if( !Rst )
		Out <= 10'd1;
	else
		Out <= {Out[14:0], Out[15]};
endmodule


module dekatronpc(CLOCK, OUT, RST_N);

input wire RST_N;
input wire CLOCK;
input wire[15:0] OUT;
wire[15:0] InstructionPtr;
wire[15:0] LoopLevel;
wire[15:0] AddressPtr;
wire[7:0] Data;

wire[7:0] InstructionSymbol;//Instruction symbol, from ROM
wire[3:0] OPCODE;//Operation, decoded from symbol

//Instruction counter wires
wire instructionPtrUp = 0;
wire instructionPtrDown = 0;

//Instruction counter wires
wire loopLevelPtrUp = 0;
wire loopLevelPtrDown = 0;

//Address counter wires
wire addressPtrUp = 0;
wire addressPtrDown = 0;

Sequenser seq(.clk(CLOCK), .out(OUT));

Counter #(.WIDTH(16), .MAX_VALUE(1000)) ipCount(.UP(instructionPtrUp), .DOWN(instructionPtrDown), .RST(RST_N), .COUNT(InstructionPtr));

Counter #(.WIDTH(7), .MAX_VALUE(100)) loopCount(.UP(loopLevelPtrUp), .DOWN(loopLevelPtrDown), .RST(RST_N), .COUNT(LoopLevel));

Counter #(.WIDTH(16), .MAX_VALUE(30000)) apCount(.UP(addressPtrUp), .DOWN(addressPtrDown), .RST(RST_N), .COUNT(AddressPtr));

ROM IP(.Address(InstructionPtr), .Data(DATA));

Encoder encoder(.symbol(DATA), .opcode(OPCODE));

always @(negedge CLOCK) 
	$display("OPCODE %d", OPCODE);



endmodule