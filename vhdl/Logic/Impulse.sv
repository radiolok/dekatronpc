module Impulse #(
    parameter EDGE = 1'b0//0 for negedge, 1 for posedge
)(
    input Clk,
    input En,
    input Rst_n,
    output wire Impulse
);
//synopsys translate_off
reg D_state;

assign Impulse = En & ~D_state;

wire Edge;

generate
if (EDGE)
    assign Edge = Clk;
else
    assign Edge = ~Clk;
endgenerate


always @(posedge Edge, negedge Rst_n) begin
    if (~Rst_n) begin
        D_state <= 1'b0;
    end
    else
    begin
        D_state <= En;
    end
end
//synopsys translate_on
endmodule
