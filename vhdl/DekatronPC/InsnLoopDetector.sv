module InsnLoopDetector #(
    parameter DATA_WIDTH = 4
)(
    input wire [DATA_WIDTH-1:0] Insn,
    output wire LoopOpen,
    output wire LoopClose
);

wire isLoopInsn;

//Loop codes: 4'b0100 for [ 
//            4'b0101 for ]
assign isLoopInsn = ~Insn[3] & Insn[2] & ~Insn[1];

assign LoopOpen = isLoopInsn & ~Insn[0];//if 4'b0100
assign LoopClose = isLoopInsn & Insn[0];//if 4'b0101

endmodule