`default_nettype none

`ifndef SYNTH
// Модель D-триггера DFF_J2N16 (vtube_cells.lib, sch/logic/DFF_J2N16): Q берёт D по СПАДУ C
// (мастер на C, ведомый на ~C). В синтезе стоит сама ячейка. RTL ставит её по имени там,
// где инверторы такта нужно разложить вручную: вход C — 4,5 сетки, на цепь не больше
// двух триггеров (10 сеток)
module DFF_J2N16 (
    input  wire C,
    input  wire D,
    output reg  Q,
    output wire QN
);
    always @(negedge C) Q <= D;
    assign QN = ~Q;
endmodule
`endif

`default_nettype wire
