function [7:0] OpcodeToSymbol (
    input [4:0] opcode
);

    casez(opcode)
      5'h?0: OpcodeToSymbol = "N";
      5'h?1: OpcodeToSymbol = "H";
      5'h02: OpcodeToSymbol = "\a";
      5'h03: OpcodeToSymbol = "\0";
      5'h04: OpcodeToSymbol = "E";
      5'h05: OpcodeToSymbol = "S";
      5'h06: OpcodeToSymbol = "{";
      5'h07: OpcodeToSymbol = "}";
      5'h08: OpcodeToSymbol = "L";
      5'h09: OpcodeToSymbol = "I";
      5'h?A: OpcodeToSymbol = "0";
      5'h0B: OpcodeToSymbol = "A";
      5'h0C: OpcodeToSymbol = "R";
      5'h0D: OpcodeToSymbol = "r";
      5'h?E: OpcodeToSymbol = "D";
      5'h?F: OpcodeToSymbol = "B";
      5'h12: OpcodeToSymbol = "+";
      5'h13: OpcodeToSymbol = "-";
      5'h14: OpcodeToSymbol = ">";
      5'h15: OpcodeToSymbol = "<";
      5'h16: OpcodeToSymbol = "[";
      5'h17: OpcodeToSymbol = "]";
      5'h18: OpcodeToSymbol = ".";
      5'h19: OpcodeToSymbol = ",";
      5'h1B: OpcodeToSymbol = "M";
      5'h1C: OpcodeToSymbol = "G";
      5'h1D: OpcodeToSymbol = "P";
      default: OpcodeToSymbol = "\0";
    endcase

endfunction
