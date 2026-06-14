module OpcodeToSymbol_wrapper(
    input wire [4:0] Opcode,
    output wire [7:0] Symbol
);
    assign Symbol = OpcodeToSymbol(Opcode);
endmodule
