module Impulse (
    input Clk,
    input En,
    input Rst_n,
    output wire Impulse
);
//synopsys translate_off
reg D_state;

assign Impulse = En & ~D_state;

always @(posedge Clk, negedge Rst_n) begin
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
