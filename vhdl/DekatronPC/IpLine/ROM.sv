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
    output wire Ready
    );
// synopsys translate_off

parameter [1:0]
    INIT      = 2'd0,
    READY     =  2'd1,
    BUSY      =  2'd2;

reg [1:0] state, next;

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) state <= INIT;
	else state <= next;
end

wire DataReady = 1; //Not used not, but for ROM delay modelling
always_comb begin
case (state)
    INIT: begin
        if (Request)
            next = BUSY;
        else
            next = INIT;
    end
    READY: begin
        if (Request)
            next = BUSY;
        else
            next = READY;
    end
    BUSY: begin
        if (DataReady)
            next = READY;
        else
            next = BUSY;
    end
    default:
        next = INIT;
endcase
end

assign Ready = ~Request & (state == READY);

wire [DATA_WIDTH-1:0] Data;

firmware #(
    .portSize(D_NUM*D_WIDTH)
    )storage(
        .Address(Address),
        .Data(Data));

always @(negedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        Insn <= {(DATA_WIDTH){1'b0}};
    end
    else begin
        if (state == BUSY)
            Insn <= Data;
    end
// synopsys translate_on
endmodule
