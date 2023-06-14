function [4:0] SymbolToOpcode (
    input [7:0] symbol,
    input [0:0] isa
    );

  casez(symbol)
    "N": SymbolToOpcode = {isa, 4'h0};
    "H": SymbolToOpcode = {isa, 4'h1};
    "\a": SymbolToOpcode = 5'h02;
    "E": SymbolToOpcode =  5'h04;
    "S": SymbolToOpcode =  5'h05;
    "{": SymbolToOpcode =  5'h06;
    "}": SymbolToOpcode =  5'h07;
    "L": SymbolToOpcode =  5'h08;
    "I": SymbolToOpcode =  5'h09;
    "0": SymbolToOpcode =  {isa, 4'hA};
    "A": SymbolToOpcode =  5'h0B;
    "R": SymbolToOpcode =  5'h0C;
    "r": SymbolToOpcode =  5'h0D;
    "D": SymbolToOpcode =  {isa, 4'hE};
    "B": SymbolToOpcode =  {isa, 4'hF};
    "+": SymbolToOpcode =  5'h12;
    "-": SymbolToOpcode =  5'h13;
    ">": SymbolToOpcode =  5'h14;
    "<": SymbolToOpcode =  5'h15;
    "[": SymbolToOpcode =  5'h16;
    "]": SymbolToOpcode =  5'h17;
    ".": SymbolToOpcode =  5'h18;
    ",": SymbolToOpcode =  5'h19;
    "M": SymbolToOpcode =  5'h1B;
    "G": SymbolToOpcode =  5'h1C;
    "P": SymbolToOpcode =  5'h1D;
    default: SymbolToOpcode = {isa, 4'h0};
  endcase

endfunction
