module IpLine(
    input wire Rst_n,
    input wire Clk,

    input wire dataIsZeroed, 

    input wire Request,
    output wire Ready,

    output reg[3:0] Insn
);

parameter DEKATRON_NUM = 6,
parameter DEKATRON_WIDTH = 3,
parameter INSN_WIDTH = 4

reg IP_Request;
reg IP_Dec;
reg IP_Set;
reg [DEKATRON_NUM*3-1:0] IP_In;

wire IP_Ready;

wire [DEKATRON_NUM*3-1:0] IP_Out;

Counter  #(
            .DEKATRON_NUM(DEKATRON_NUM),
            .DEKATRON_WIDTH(DEKATRON_WIDTH),
            .COUNT_DELAY(3)
            )IP_counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(IP_Dec),
                .Set(IP_Set),
                .In(IP_In),
                .Ready(IP_Ready),
                .Out(IP_Out)
            );

wire [INSN_WIDTH-1:0] TmpInsnReg;
reg [INSN_WIDTH-1:0] InsnReg;

reg ROM_Request;
wire ROM_Ready;

ROM #(
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(IP_Out),
        .Insn(Insn),
        .Request(ROM_Request),
        .Ready(ROM_Ready)
        );

endmodule