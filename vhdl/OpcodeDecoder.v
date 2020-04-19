module OpcodeDecoder(opcode, Out);
    input wire [3:0] opcode;
    output wire [15:0] Out;

    assign Out[0] =  ~opcode[0] &   ~opcode[1] &  ~opcode[2] &  ~opcode[3];  
    assign Out[1] =   opcode[0] &   ~opcode[1] &  ~opcode[2] &  ~opcode[3];  
    assign Out[2] =  ~opcode[0] &    opcode[1] &  ~opcode[2] &  ~opcode[3];  
    assign Out[3] =   opcode[0] &    opcode[1] &  ~opcode[2] &  ~opcode[3];  
    assign Out[4] =  ~opcode[0] &   ~opcode[1] &   opcode[2] &  ~opcode[3];  
    assign Out[5] =   opcode[0] &   ~opcode[1] &   opcode[2] &  ~opcode[3];  
    assign Out[6] =  ~opcode[0] &    opcode[1] &   opcode[2] &  ~opcode[3];  
    assign Out[7] =   opcode[0] &    opcode[1] &   opcode[2] &  ~opcode[3];  
    assign Out[8] =  ~opcode[0] &   ~opcode[1] &  ~opcode[2] &   opcode[3];  
    assign Out[9] =   opcode[0] &   ~opcode[1] &  ~opcode[2] &   opcode[3];  
    assign Out[10] = ~opcode[0] &    opcode[1] &  ~opcode[2] &   opcode[3];  
    assign Out[11] =  opcode[0] &    opcode[1] &  ~opcode[2] &   opcode[3];  
    assign Out[12] = ~opcode[0] &   ~opcode[1] &   opcode[2] &   opcode[3];  
    assign Out[13] =  opcode[0] &   ~opcode[1] &   opcode[2] &   opcode[3];  
    assign Out[14] = ~opcode[0] &    opcode[1] &   opcode[2] &   opcode[3];  
    assign Out[15] =  opcode[0] &    opcode[1] &   opcode[2] &   opcode[3];  

endmodule