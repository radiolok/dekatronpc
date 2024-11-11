module SymbolToInsn(Symbol, Insn);
//Symbol to opcode
input logic [7:0] Symbol;
output logic [3:0] Insn;

always_comb
    case(Symbol)
    8'h2B : Insn <= 4'b0001; //+
    8'h2D : Insn <= 4'b0010;//-
    8'h3E: Insn <= 4'b0011;//>
    8'h3C: Insn <= 4'b0100;//<
    8'h5B: Insn <= 4'b0101;//[
    8'h5D: Insn <= 4'b0110;//]
    8'h2E: Insn <= 4'b0111;//.
    8'h2C: Insn <= 4'b1000;//,
    default: Insn <= 4'b0000;//NOP
    endcase

endmodule



