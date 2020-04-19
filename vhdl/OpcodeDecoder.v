module InsnDecoder(Insn, Opcode);
    input wire [3:0] Insn;
    output wire [15:0] Opcode;

    assign Opcode[0] =  ~Insn[0] &   ~Insn[1] &  ~Insn[2] &  ~Insn[3];  
    assign Opcode[1] =   Insn[0] &   ~Insn[1] &  ~Insn[2] &  ~Insn[3];  
    assign Opcode[2] =  ~Insn[0] &    Insn[1] &  ~Insn[2] &  ~Insn[3];  
    assign Opcode[3] =   Insn[0] &    Insn[1] &  ~Insn[2] &  ~Insn[3];  
    assign Opcode[4] =  ~Insn[0] &   ~Insn[1] &   Insn[2] &  ~Insn[3];  
    assign Opcode[5] =   Insn[0] &   ~Insn[1] &   Insn[2] &  ~Insn[3];  
    assign Opcode[6] =  ~Insn[0] &    Insn[1] &   Insn[2] &  ~Insn[3];  
    assign Opcode[7] =   Insn[0] &    Insn[1] &   Insn[2] &  ~Insn[3];  
    assign Opcode[8] =  ~Insn[0] &   ~Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[9] =   Insn[0] &   ~Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[10] = ~Insn[0] &    Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[11] =  Insn[0] &    Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[12] = ~Insn[0] &   ~Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[13] =  Insn[0] &   ~Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[14] = ~Insn[0] &    Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[15] =  Insn[0] &    Insn[1] &   Insn[2] &   Insn[3];  

endmodule