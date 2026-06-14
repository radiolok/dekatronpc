module SymbolToOpcode_wrapper(
    input wire [7:0] Symbol,
    input wire [0:0] isa,
    output wire [4:0] Opcode
);
    assign Opcode = SymbolToOpcode(Symbol, isa);
endmodule
