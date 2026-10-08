// Импульс по фронту En длительностью до следующего фронта Clk.
//
// `DEKATRON_DELAY_MODEL: модель без тактовой базы. Clk не используется,
// длительность импульса — HS_NS нс (один такт hsClk 10 МГц, который
// заменяет модель). Только для Icarus; в нетлисте Impulse — чёрный ящик.
module Impulse #(
    parameter HS_NS = 100   // длительность импульса в модели на задержках, нс
)(
/* verilator lint_off UNUSEDSIGNAL */
    input Clk,
/* verilator lint_on UNUSEDSIGNAL */
    input En,
    input Rst_n,
    output wire Impulse
);
`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
timeunit 1ns;
timeprecision 1ps;

// En, каким он был HS_NS назад. Присваивание инерционное: En короче
// HS_NS сюда не доходит, и импульс равен самому En, как и в тактовой
// модели, когда En не застаёт ни одного фронта Clk.
wire D_state;
assign #(HS_NS) D_state = En & Rst_n;

assign Impulse = En & ~(D_state & Rst_n);
`else
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
`endif
`endif
endmodule
