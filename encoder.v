module Encoder(symbol, opcode);

input [7:0] symbol;
output reg [3:0] opcode;

always @(symbol)

begin

case(symbol)
8'h2B : opcode = 4'b0001; //+
8'h2D : opcode = 4'b0010;//-
8'h3E: opcode = 4'b0011;//>
8'h3C: opcode = 4'b0100;//<
8'h5B: opcode = 4'b0101;//[
8'h5D: opcode = 4'b0110;//]
8'h2E: opcode = 4'b0111;//.
8'h2C: opcode = 4'b1000;//,
default: opcode = 4'b0000;
endcase

end

endmodule

