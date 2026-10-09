/* Hand-written hierarchy for test/parsers/verilog.test.ts, in Yosys write_verilog style */

(* blackbox *)
module Stub(a, y);
  input a;
  wire a;
  output y;
  wire y;
  assign y = 1'hx;
endmodule

// Not instantiated anywhere: must not count as a top candidate
module Unused(a);
  input a;
endmodule

module \$paramod\Pair\W=32'00000000000000000000000000000010 (in, out, en);
  input [1:0] in;
  wire [1:0] in;
  output [1:0] out;
  wire [1:0] out;
  input en;
  wire en;
  wire [1:0] mid;
  wire _005_;
  NAND2 \g[0].u  (.A(in[0]), .B(en), .Y(mid[0]));
  NAND2 \g[1].u  (.A(in[1]), .B(en), .Y(_005_));
  NOT inv0 (.A(mid[0]), .Y(out[0]));
  Stub s (.a(mid[1]), .y(out[1]));
  assign mid[1] = _005_;
endmodule

module Top(clk, d, q, tie);
  input clk;
  wire clk;
  input [3:0] d;
  wire [3:0] d;
  output [3:0] q;
  wire [3:0] q;
  output tie;
  wire tie;
  wire [3:0] w;
  \$paramod\Pair\W=32'00000000000000000000000000000010  p0 (.in(d[1:0]), .out(w[1:0]), .en(clk));
  \$paramod\Pair\W=32'00000000000000000000000000000010  p1 (.in({ d[3], d[2] }), .out(w[3:2]), .en(1'h1));
  REG4 r (.D(w), .C(clk), .Q(q));
  assign tie = 1'h0;
endmodule
