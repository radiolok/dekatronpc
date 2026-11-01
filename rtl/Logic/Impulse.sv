// Импульс по фронту En длительностью до следующего фронта Clk.
// FALL = 1: по спаду En (в железе — дифференцирующая RC-цепь на заднем
// фронте; так DekatronPhaseGen запускает вторую фазу концом первой).
//
// `DEKATRON_DELAY_MODEL: модель на задержках, тактовой базы нет вовсе —
// нет и порта Clk; импульс длится WIDTH_NS нс (дифференцирующая RC-цепь,
// TRS v0.25). Только для Icarus; в нетлисте Impulse — чёрный ящик.
module Impulse #(
    parameter WIDTH_NS = 100,  // длительность импульса в модели на задержках, нс
    parameter bit FALL = 1'b0  // 1: импульс по спаду En
)(
`ifndef DEKATRON_DELAY_MODEL
    input Clk,
`endif
    input En,
    input Rst_n,
    output wire Impulse
);
`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
timeunit 1ns;
timeprecision 1ps;

// En, каким он был WIDTH_NS назад. Присваивание инерционное: En короче
// WIDTH_NS сюда не доходит, и импульс равен самому En, как и в тактовой
// модели, когда En не застаёт ни одного фронта Clk.
wire D_state;
assign #(WIDTH_NS) D_state = En & Rst_n;

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
