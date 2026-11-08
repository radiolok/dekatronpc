`default_nettype none

`ifndef SYNTH
// Модель ячейки A1OOI_N16J2 (vtube_cells.lib, sch/logic/A1OOI_N16J2):
// И-ИЛИ-НЕ, Y = ~((A · B) + C) — 6Ж2Б (A на g1, B на g3) и триод 6Н16Б
// (C) на общем аноде. В синтезе стоит сама ячейка: RTL ставит её по имени
// там, где схема собрана вручную (WriteLineDec, TRS v0.56)
module A1OOI_N16J2 (input wire A, input wire B, input wire C, output wire Y);
    assign Y = ~((A & B) | C);
endmodule
`endif

`default_nettype wire
