module ROM #(
    parameter DEKATRON_NUM = 6,
    parameter DEKATRON_WIDTH = 3,
    parameter DATA_WIDTH = 4
)(
    input wire Clk, 
    input wire Rst_n, 
    input wire [DEKATRON_NUM*DEKATRON_WIDTH-1:0]Address, 
    output reg[DATA_WIDTH-1:0] Insn
    );

//wire [15:0] StorageData;
wire [DATA_WIDTH-1:0] ActiveInsn ;/*Address[1] ? 
            (Address[0]? StorageData[15:12] : StorageData[11:8]):
            (Address[0]? StorageData[7:4] : StorageData[3:0]);*/

`ifdef LOOP_TEST
    loopTest storage(.Address(Address),
                        .Data(ActiveInsn));
`else
    helloworld storage(.Address(Address),
                        .Data(ActiveInsn));
`endif

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n)
        Insn <= (DATA_WIDTH){1'b0000};
    else
        Insn <= ActiveInsn;

endmodule

