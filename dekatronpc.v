`timescale 1 ns / 1 ps


module Sequenser(clk, out);

input wire clk;

output reg[15:0] out = 1'b1;

reg[3:0] count = 1'b0;


always 

@(posedge clk) begin
	count <= count + 1'b1;
	if (count == 0)
		 out <= 1'b1;
	else
		out <= out << 1;
end

endmodule


module shiftReg(clk, in, rst, out);

input wire clk;
input wire in;
input wire rst;
output reg out;

reg[1:0] internal = 2'b00;

always @(posedge clk) begin
	assign out = in;
end
/*
always @(posedge clk) begin
	if (rst == 0) begin
		internal <= 1'b0;
		assign out <= internal[0];
		end
	else
		internal[0] <= in;
end

always @(negedge clk) begin
  assign  out <= internal[0];
end*/

endmodule



module dekatronpc(CLOCK, OUT, RST_N);

input wire RST_N;
input wire CLOCK;
input wire[15:0] OUT;
wire[15:0] COUNTER;
wire[7:0] DATA;

wire[3:0] OPCODE;

wire DOWN = 0;

Sequenser seq(.clk(CLOCK), .out(OUT));

Counter #(.WIDTH(16)) count(.UP(CLOCK), .DOWN(DOWN), .RST(RST_N), .COUNT(COUNTER));

ROM IP(.Address(COUNTER), .Data(DATA));

Encoder encoder(.symbol(DATA), .opcode(OPCODE));

always @(negedge CLOCK) begin

	$display("OPCODE %d", OPCODE);
end


endmodule