module IpLine(
    input wire Rst_n,
    input wire Count,
    input wire Reverse,
    input wire Load,
    output reg[15:0] Opcode
);

wire[23:0] IpAddress;

CounterIp IP(.Step(Count),
            .Reverse(Reverse), 
            .Rst_n(Rst_n), 
            .Out(IpAddress));

wire [7:0] Data;
wire [3:0] Insn;
wire [15:0] _Opcode;

ROM rom(.Address(IpAddress),
        .Data(Data));

SymbolToInsn symbolToInsn(.Symbol(Data),
                            .Insn(Insn));

OpcodeDecoder opcodeDecoder(.Insn(Insn),
                            .Opcode(_Opcode));

always @(posedge Load)
    Opcode <= _Opcode;

endmodule