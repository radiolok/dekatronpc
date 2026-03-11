module InsnTransmissionDetector(
    input wire InsnMode,
    input wire [INSN_WIDTH-1:0] Insn,
    output wire StartOfTransmission,
    output wire EndOfTransmission
);

wire isTransmissionInsn;

//Insn codes: 4'b0100 for EOT 
//            4'b0101 for SOT
assign isTransmissionInsn = ~InsnMode & ~Insn[3] & Insn[2] & ~Insn[1];

assign StartOfTransmission = isTransmissionInsn & Insn[0];//if 4'b0100
assign EndOfTransmission = isTransmissionInsn & ~Insn[0];//if 4'b0101

endmodule
