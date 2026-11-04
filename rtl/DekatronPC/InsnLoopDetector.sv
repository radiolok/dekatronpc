module InsnLoopDetector(
    input wire [3:0] Insn,
    output wire LoopOpen,
    output wire LoopClose
);

wire isLoopInsn;

// Loop codes (ISA16, doc/isa16.md): 4'b0110 [   4'b0111 ]
//                                   4'b1110 {   4'b1111 }
// Bit 3 (what is tested) does not matter here: the scan counts both kinds
// together, so [ ] and { } must not be interleaved
assign isLoopInsn = Insn[2] & Insn[1];

assign LoopOpen  = isLoopInsn & ~Insn[0];
assign LoopClose = isLoopInsn &  Insn[0];

endmodule
