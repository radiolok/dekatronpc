module SymbolToOpcode_wrapper(
    input wire [7:0] Symbol,
    output wire [3:0] Opcode
);
    assign Opcode = SymbolToOpcode(Symbol);
endmodule
