(* keep_hierarchy = "yes" *) module ROM #(
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
    output reg DataReady
    );

wire [DATA_WIDTH-1:0] ActiveInsn;

//`ifdef LOOP_TEST
    looptest storage(.Address(Address),
                        .Data(ActiveInsn));
//`else
//    helloworld storage(.Address(Address),
//                        .Data(ActiveInsn));
//`endif
reg Busy;
always @(negedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        Insn <= {(DATA_WIDTH){1'b0}};
        DataReady <= 1'b0;
        Busy <= 1'b0;
    end
    else begin
        if (Request) begin
            Insn <= ActiveInsn;
            DataReady <= 1'b0;
            Busy <= 1'b1;
		end
        if (Busy) begin
            Busy <= 1'b0;
            DataReady <= 1'b1;
        end
    end
endmodule

