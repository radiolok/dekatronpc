module OpcodeDecoder(Insn, Opcode);
    input wire [3:0] Insn;
    output wire [15:0] Opcode;

    assign Opcode[0] =  ~Insn[0] &   ~Insn[1] &  ~Insn[2] &  ~Insn[3];  //NOP     b0000 OP0
    assign Opcode[1] =   Insn[0] &   ~Insn[1] &  ~Insn[2] &  ~Insn[3];  //+       b0001 OP1
    assign Opcode[2] =  ~Insn[0] &    Insn[1] &  ~Insn[2] &  ~Insn[3];  //-       b0010 OP2
    assign Opcode[3] =   Insn[0] &    Insn[1] &  ~Insn[2] &  ~Insn[3];  //>       b0011 OP3
    assign Opcode[4] =  ~Insn[0] &   ~Insn[1] &   Insn[2] &  ~Insn[3];  //<       b0100 OP4
    assign Opcode[5] =   Insn[0] &   ~Insn[1] &   Insn[2] &  ~Insn[3];  //[       b0101 OP5
    assign Opcode[6] =  ~Insn[0] &    Insn[1] &   Insn[2] &  ~Insn[3];  //]       b0110 OP6
    assign Opcode[7] =   Insn[0] &    Insn[1] &   Insn[2] &  ~Insn[3];  //.(cout) b0111 OP7
    assign Opcode[8] =  ~Insn[0] &   ~Insn[1] &  ~Insn[2] &   Insn[3];  //,(cin)  b1000 OP8
    assign Opcode[9] =   Insn[0] &   ~Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[10] = ~Insn[0] &    Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[11] =  Insn[0] &    Insn[1] &  ~Insn[2] &   Insn[3];  
    assign Opcode[12] = ~Insn[0] &   ~Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[13] =  Insn[0] &   ~Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[14] = ~Insn[0] &    Insn[1] &   Insn[2] &   Insn[3];  
    assign Opcode[15] =  Insn[0] &    Insn[1] &   Insn[2] &   Insn[3];  //HALT    b1111 OP15

endmodule