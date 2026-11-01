// Импульс по фронту En длительностью до следующего фронта Clk.
// FALL = 1: по спаду En (в железе — дифференцирующая RC-цепь на заднем
// фронте; так DekatronPhaseGen запускает вторую фазу концом первой).
//
// `DEKATRON_DELAY_MODEL: модель без тактовой базы. Clk не используется,
// длительность импульса — HS_NS нс (один такт hsClk, который заменяет
// модель). Только для Icarus; в нетлисте Impulse — чёрный ящик.
// Период hsClk в модели на задержках, нс: Clk / 10 (rtl/parameters.sv,
// DEKATRON_CLK_NS, TRS v0.24). Запасное умолчание — для сборок без
// parameters.sv (cocotb)
`ifndef DEKATRON_HS_NS
`define DEKATRON_HS_NS 1000
`endif
module Impulse #(
    parameter HS_NS = `DEKATRON_HS_NS,  // длительность импульса в модели на задержках, нс
    parameter bit FALL = 1'b0  // 1: импульс по спаду En
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

generate
    if (FALL) begin : gen_fall
        assign Impulse = ~En & D_state & Rst_n;
    end
    else begin : gen_rise
        assign Impulse = En & ~(D_state & Rst_n);
    end
endgenerate
`else
reg D_state;

generate
    if (FALL) begin : gen_fall
        assign Impulse = ~En & D_state;
    end
    else begin : gen_rise
        assign Impulse = En & ~D_state;
    end
endgenerate

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
