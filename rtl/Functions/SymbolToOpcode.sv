// ISA16 (doc/isa16.md): one 4-bit instruction set, same table as
// rtl/run/generate_rom.py. Unknown symbols give NOP.
function logic [3:0] SymbolToOpcode (
    input [7:0] symbol
    );

  case(symbol)
    " ": SymbolToOpcode = 4'h0;
    "N": SymbolToOpcode = 4'h0;
    "H": SymbolToOpcode = 4'h1;
    "+": SymbolToOpcode = 4'h2;
    "-": SymbolToOpcode = 4'h3;
    ">": SymbolToOpcode = 4'h4;
    "<": SymbolToOpcode = 4'h5;
    "[": SymbolToOpcode = 4'h6;
    "]": SymbolToOpcode = 4'h7;
    ".": SymbolToOpcode = 4'h8;
    ",": SymbolToOpcode = 4'h9;
    "0": SymbolToOpcode = 4'hA;   // [-]
    "S": SymbolToOpcode = 4'hB;   // LD: start of loading
    "E": SymbolToOpcode = 4'hB;   // LD: end of loading (EOT)
    "A": SymbolToOpcode = 4'hC;   // CLRA
    "P": SymbolToOpcode = 4'hD;   // MemLock
    "{": SymbolToOpcode = 4'hE;
    "}": SymbolToOpcode = 4'hF;
    default: SymbolToOpcode = 4'h0;
  endcase

endfunction
