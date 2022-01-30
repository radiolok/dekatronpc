module ROM #(
    parameter DEKATRON_NUM = 6,
    parameter DEKATRON_WIDTH = 3,
    parameter DATA_WIDTH = 4,
    parameter COUNT_DELAY = 2//delay in clockticks between Req and Rdy
)(
    input wire Clk, 
    input wire Rst_n, 

    input wire [DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address, 
    output reg[DATA_WIDTH-1:0] Insn,

    input wire Request,
    output wire Ready
    );

wire [DATA_WIDTH-1:0] ActiveInsn;

reg [COUNT_DELAY-1:0] delay_shifter;
assign Ready = delay_shifter[0];

`ifdef LOOP_TEST
    loopTest storage(.Address(Address),
                        .Data(ActiveInsn));
`else
    helloworld storage(.Address(Address),
                        .Data(ActiveInsn));
`endif

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        delay_shifter <= {{(COUNT_DELAY-1){1'b0}}, 1'b1};
        Insn <= (DATA_WIDTH){1'b0000};
    end
    else
        if (~(Ready & ~Request)) begin // Simulate internal logic delay.
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
        end
        if (Ready & Request)
            Insn <= ActiveInsn;

endmodule

