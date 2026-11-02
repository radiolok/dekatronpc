// ISA16 (doc/isa16.md): printable symbol of an opcode. LD prints as "S".
function [7:0] OpcodeToSymbol (
    input [3:0] opcode
);

    case(opcode)
      4'h0: OpcodeToSymbol = " ";
      4'h1: OpcodeToSymbol = "H";
      4'h2: OpcodeToSymbol = "+";
      4'h3: OpcodeToSymbol = "-";
      4'h4: OpcodeToSymbol = ">";
      4'h5: OpcodeToSymbol = "<";
      4'h6: OpcodeToSymbol = "[";
      4'h7: OpcodeToSymbol = "]";
      4'h8: OpcodeToSymbol = ".";
      4'h9: OpcodeToSymbol = ",";
      4'hA: OpcodeToSymbol = "0";
      4'hB: OpcodeToSymbol = "S";
      4'hC: OpcodeToSymbol = "A";
      4'hD: OpcodeToSymbol = "P";
      4'hE: OpcodeToSymbol = "{";
      default: OpcodeToSymbol = "}";
    endcase

endfunction
