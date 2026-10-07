// DekatronPC vacuum-tube standard cells - behavioral Verilog models.
// Companion library to vtube_cells.lib and vtube_cells.sp.
// Cell names and pin order follow vtube_cells.lib.

module BUF_6N16B(A, Y);
input A;
output Y;
assign Y = A;
endmodule

module BUF_6J2B(A, Y);
input A;
output Y;
assign Y = A;
endmodule

module NOT_6N16B(A, Y);
input A;
output Y;
assign Y = ~A;
endmodule

module NOT_6J2B(A, Y);
input A;
output Y;
assign Y = ~A;
endmodule

module NAND2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = ~(A & B);
endmodule

module AND2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = A & B;
endmodule

module NAND2_J2(A, B, Y);
input A, B;
output Y;
assign Y = ~(A & B);
endmodule

module NAND4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A & B & C & D);
endmodule

module A1OOI_N16X7(A, B, C, Y);
input A, B, C;
output Y;
assign Y = ~((A & B) | C);
endmodule

module A2OOI_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~((A & B) | C | D);
endmodule

module OR2_N16(A, B, Y);
input A, B;
output Y;
assign Y = A | B;
endmodule

module OR2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = A | B;
endmodule

module OR4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = A | B | C | D;
endmodule

module OR10_X7(A, B, C, D, E, F, G, H, K, L, Y);
input A, B, C, D, E, F, G, H, K, L;
output Y;
assign Y = A | B | C | D | E | F | G | H | K | L;
endmodule

module NOR2_N16(A, B, Y);
input A, B;
output Y;
assign Y = ~(A | B);
endmodule

module NOR4_N16(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A | B | C | D);
endmodule

module NOR2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = ~(A | B);
endmodule

module NOR4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A | B | C | D);
endmodule

module LATCH(C, D, Q);
input C, D;
output reg Q;
always @(*)
	if (C)
		Q = D;
endmodule

module DFF(C, D, Q);
input C, D;
output reg Q;
always @(posedge C)
	Q <= D;
endmodule

module DFFSR(C, D, Q, S, R);
input C, D, S, R;
output reg Q;
always @(posedge C, posedge S, posedge R)
	if (S)
		Q <= 1'b1;
	else if (R)
		Q <= 1'b0;
	else
		Q <= D;
endmodule

module DFFSR_n(C, D, Q, S, R);
input C, D, S, R;
output reg Q;
always @(posedge C, posedge S, negedge R)
	if (S)
		Q <= 1'b1;
	else if (!R)
		Q <= 1'b0;
	else
		Q <= D;
endmodule

module TIEHI(H);
output H;
assign H = 1'b1;
endmodule

module TIELO(L);
output L;
assign L = 1'b0;
endmodule

// Relay, two changeover contacts. Not a tube; COIL only from panel switches.
module RELAY_2CO(COIL, NC1, NO1, NC2, NO2, C1, C2);
input COIL, NC1, NO1, NC2, NO2;
output C1, C2;
assign C1 = COIL ? NO1 : NC1;
assign C2 = COIL ? NO2 : NC2;
endmodule
