`default_nettype none

`ifndef SYNTH
// Модель ячейки NOR3_N16 (vtube_cells.lib, sch/logic/): трёхвходовое ИЛИ-НЕ на полутора 6Н16Б. В синтезе
// стоит сама ячейка: RTL ставит её по имени там, где схема собрана вручную
// (IpLine — вентиль сброса автомата TC-N2, WriteLineDec — дешифратор
// записи TRS v0.56), и ABC её не растворяет
module NOR3_N16 (input wire A, input wire B, input wire C, output wire Y);
    assign Y = ~(A | B | C);
endmodule
`endif

`default_nettype wire
