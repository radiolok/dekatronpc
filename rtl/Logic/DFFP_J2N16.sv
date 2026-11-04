`default_nettype none

`ifndef SYNTH
// Модель импульсного D-триггера (ячейка vtube_cells.lib DFFP_J2N16,
// sch/logic/DFFP2_J2N16, TC-N5): Q берёт D по нарастающему фронту C.
// 3,5 лампы против 7 у DFF_J2N16. В синтезе стоит сама ячейка: у неё
// dont_use, dfflibmap её не выбирает, RTL ставит её по имени там, где
// подходят её выводы: D — ВВ-вход (в ячейке свои делители, не больше двух
// таких D на цепь), C — ВВ-линия такта.
module DFFP_J2N16 (
    input  wire C,
    input  wire D,
    output reg  Q,
    output wire QN
);
    always @(posedge C) Q <= D;
    assign QN = ~Q;
endmodule
`endif
