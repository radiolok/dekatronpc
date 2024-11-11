module yam430_register #(
    parameter DATA_WIDTH = 8
)(
    input wire Rst_n,
    input wire Clk,
    input wire Wr,
    input wire [DATA_WIDTH-1:0] Data,
    output reg [DATA_WIDTH-1:0] Q,
    output wire [DATA_WIDTH-1:0] Q_n
);

assign Q_n = ~Q;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) Q <= {DATA_WIDTH{1'b0}};
    else if (Wr) Q <= Data;
end
endmodule

module yam430_reg_gile #(
    parameter DATA_WIDTH=8,
    parameter REG_NUMBER=16
)(
    input Rst_n,
    input Clk,
    input wire[(DATA_WIDTH*REG_NUMBER)-1:0] Data,
    output wire[(DATA_WIDTH*REG_NUMBER)-1:0] Q,
    output wire[(DATA_WIDTH*REG_NUMBER)-1:0] Q_n,
    input wire [REG_NUMBER-1:0] Wr
);

genvar i;
generate
    for (i = 0; i < REG_NUMBER; i = i+1)  begin: registers
        yam430_register #(.DATA_WIDTH(DATA_WIDTH)) yam430_reg(
            .Rst_n(Rst_n),
            .Clk(Clk),
            .Wr(Wr[i]),
            .Data(Data),
            .Q(Q[(DATA_WIDTH*(i+1))-1: (DATA_WIDTH*i)]),
            .Q_n(Q_n[(DATA_WIDTH*(i+1))-1: (DATA_WIDTH*i)])
        );
    end
endgenerate

endmodule