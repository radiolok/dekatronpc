`default_nettype none

`ifndef SYNTH
// Модель ячейки NOR2_N16 (vtube_cells.lib, sch/logic/): двухвходовое ИЛИ-НЕ на одной 6Н16Б. В синтезе
// стоит сама ячейка: RTL ставит её по имени там, где схема собрана вручную
// (IpLine — вентиль сброса автомата TC-N2, WriteLineDec — дешифратор
// записи TRS v0.56), и ABC её не растворяет
module NOR2_N16 (input wire A, input wire B, output wire Y);
    assign Y = ~(A | B);
endmodule
`endif

`default_nettype wire
