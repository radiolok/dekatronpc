`default_nettype none

`ifndef SYNTH
// Модель ячейки NOT_N16 (vtube_cells.lib, sch/logic/): инвертор на половине 6Н16Б. В синтезе
// стоит сама ячейка: RTL ставит её по имени там, где схема собрана вручную
// (IpLine — вентиль сброса автомата TC-N2, WriteLineDec — дешифратор
// записи TRS v0.56), и ABC её не растворяет
module NOT_N16 (input wire A, output wire Y);
    assign Y = ~A;
endmodule
`endif

`default_nettype wire
