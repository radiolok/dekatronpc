(* keep_hierarchy = "yes" *) module ROM #(
    parameter D_NUM = 6,
    parameter D_WIDTH = 4,
    parameter DATA_WIDTH = 4
)(
    input wire Clk, 
    input wire Rst_n, 

    input wire [D_NUM*D_WIDTH-1:0] Address, 
    output reg[DATA_WIDTH-1:0] Insn,

    input wire Request,
    output reg DataReady
    );

wire [DATA_WIDTH-1:0] ActiveInsn;

//`ifdef LOOP_TEST
//    helloworld #(
    looptest #(
        .portSize(D_NUM*D_WIDTH)
        ) storage(
            .Address(Address),
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
