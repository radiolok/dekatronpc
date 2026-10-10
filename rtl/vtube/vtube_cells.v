// DekatronPC vacuum-tube standard cells - behavioral Verilog models.
// Companion library to vtube_cells.lib and vtube_cells.sp.
// Cell names, pins and functions follow vtube_cells.lib one to one: the
// netlist simulation (rtl/run/synth_sim.sh) checks that every liberty cell
// has a model here.
// Zero-delay models: a flop's Q changes on the clock edge, as in RTL.
// Each cell has a specify block with every input-to-output path at delay 0.
// Without iverilog -gspecify the blocks are ignored and nothing changes;
// with it, $sdf_annotate puts the delays of vtube_timing.json on these
// paths (synth_sim.sh -t, rtl/run/vtube_sdf.py, doc/vtube_sdf_timing.md).

module BUF_N16(A, Y);
input A;
output Y;
assign Y = A;
specify
	(A => Y) = 0;
endspecify
endmodule

module BUF_6J2B(A, Y);
input A;
output Y;
assign Y = A;
specify
	(A => Y) = 0;
endspecify
endmodule

module NOT_N16(A, Y);
input A;
output Y;
assign Y = ~A;
specify
	(A => Y) = 0;
endspecify
endmodule

module NOT_J2(A, Y);
input A;
output Y;
assign Y = ~A;
specify
	(A => Y) = 0;
endspecify
endmodule

module NAND2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = ~(A & B);
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module AND2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = A & B;
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module NAND2_J2(A, B, Y);
input A, B;
output Y;
assign Y = ~(A & B);
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module NAND4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A & B & C & D);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
endspecify
endmodule

module A1OOI_N16J2(A, B, C, Y);
input A, B, C;
output Y;
assign Y = ~((A & B) | C);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
endspecify
endmodule

module A2OOI_J2(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~((A & B) | C | D);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
endspecify
endmodule

module OR2_N16(A, B, Y);
input A, B;
output Y;
assign Y = A | B;
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module OR2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = A | B;
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module OR4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = A | B | C | D;
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
endspecify
endmodule

module OR10_X7(A, B, C, D, E, F, G, H, K, L, Y);
input A, B, C, D, E, F, G, H, K, L;
output Y;
assign Y = A | B | C | D | E | F | G | H | K | L;
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
	(E => Y) = 0;
	(F => Y) = 0;
	(G => Y) = 0;
	(H => Y) = 0;
	(K => Y) = 0;
	(L => Y) = 0;
endspecify
endmodule

module NOR2_N16(A, B, Y);
input A, B;
output Y;
assign Y = ~(A | B);
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module NOR4_N16(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A | B | C | D);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
endspecify
endmodule

module NOR2_N16X7(A, B, Y);
input A, B;
output Y;
assign Y = ~(A | B);
specify
	(A => Y) = 0;
	(B => Y) = 0;
endspecify
endmodule

module NOR4_N16X7(A, B, C, D, Y);
input A, B, C, D;
output Y;
assign Y = ~(A | B | C | D);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
endspecify
endmodule

module NOR10_N16X7(A, B, C, D, E, F, G, H, K, L, Y);
input A, B, C, D, E, F, G, H, K, L;
output Y;
assign Y = ~(A | B | C | D | E | F | G | H | K | L);
specify
	(A => Y) = 0;
	(B => Y) = 0;
	(C => Y) = 0;
	(D => Y) = 0;
	(E => Y) = 0;
	(F => Y) = 0;
	(G => Y) = 0;
	(H => Y) = 0;
	(K => Y) = 0;
	(L => Y) = 0;
endspecify
endmodule

// Triggers: Q and QN are both anodes of the tube trigger (qn_absorb.py
// moves inverters on Q to QN), so every trigger has both outputs.
module LATCH(C, D, Q, QN);
input C, D;
output reg Q;
output QN;
assign QN = ~Q;
always @*
	if (C)
		Q = D;
specify
	(D => Q) = 0;
	(D => QN) = 0;
	(posedge C => (Q +: D)) = 0;
	(posedge C => (QN -: D)) = 0;
endspecify
endmodule

module DFF(C, D, Q, QN);
input C, D;
output reg Q;
output QN;
assign QN = ~Q;
always @(posedge C)
	Q <= D;
specify
	(posedge C => (Q +: D)) = 0;
	(posedge C => (QN -: D)) = 0;
endspecify
endmodule

// clear: R, preset: S, both active high; preset wins as in Yosys $_DFFSR_
module DFFSR(C, D, Q, QN, S, R);
input C, D, S, R;
output reg Q;
output QN;
assign QN = ~Q;
always @(posedge C, posedge S, posedge R)
	if (S)
		Q <= 1'b1;
	else if (R)
		Q <= 1'b0;
	else
		Q <= D;
specify
	(posedge C => (Q +: D)) = 0;
	(posedge C => (QN -: D)) = 0;
	(S => Q) = 0;
	(S => QN) = 0;
	(R => Q) = 0;
	(R => QN) = 0;
endspecify
endmodule

// clear: R' (active low), preset: S (active high)
module DFFSR_n(C, D, Q, QN, S, R);
input C, D, S, R;
output reg Q;
output QN;
assign QN = ~Q;
always @(posedge C, posedge S, negedge R)
	if (S)
		Q <= 1'b1;
	else if (!R)
		Q <= 1'b0;
	else
		Q <= D;
specify
	(posedge C => (Q +: D)) = 0;
	(posedge C => (QN -: D)) = 0;
	(S => Q) = 0;
	(S => QN) = 0;
	(R => Q) = 0;
	(R => QN) = 0;
endspecify
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
specify
	(COIL => C1) = 0;
	(NC1 => C1) = 0;
	(NO1 => C1) = 0;
	(COIL => C2) = 0;
	(NC2 => C2) = 0;
	(NO2 => C2) = 0;
endspecify
endmodule

module GUIDE_EN_J2(EN, G, Y);
input EN, G;
output Y;
assign Y = G & EN;
specify
	(EN => Y) = 0;
	(G => Y) = 0;
endspecify
endmodule
