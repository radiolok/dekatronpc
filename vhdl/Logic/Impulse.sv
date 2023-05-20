module Impulse #(
    parameter EDGE = 0//0 for negedge, 1 for posedge
)(
    input Clk,
    input En,
    input Rst_n,
    output wire Impulse
);

reg D_state;

assign Impulse = En & ~D_state;

wire Edge;

if (EDGE)
    assign Edge = Clk;
else
    assign Edge = ~Clk;

always @(posedge Edge, negedge Rst_n) begin
    if (~Rst_n) begin
        D_state <= 1'b0;
    end
    else
    begin
        D_state <= En;
    end
end
endmodule
