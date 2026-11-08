//======================================================================
// ClkTree — тактовое дерево платы такта в MachineCtrl (TRS v0.61,
// REQ-CLK-006, doc/clock_tree.md)
//
//   генератор / внешний вход (переключатель)
//        │ clk
//     NOT_N16 clkGen        выходной каскад генератора: фаза, при которой
//        │ clk_gen_n        после второго инвертора DFFP видят прямой Clk
//        ├──► NOT_N16 ──► clk_ip          IpLine: все DFFP; внутри блока ещё
//        │                                один NOT_N16 для DFF_J2N16
//        ├──► NOT_N16 ──► clk_ap          ApLine: так же
//        ├──► NOT_N16 ──► clk_ipm         ферритовая память программ (IpMemory)
//        ├──► NOT_N16 ──► clk_apm         ферритовая память данных (Ram)
//        ├──► NOT_N16 ──► clk_loc[0]      MachineCtrl: 7 DFFP
//        ├──► NOT_N16 ──► clk_loc[1]      MachineCtrl: 6 DFFP
//        └──► NOT_N16 ──► clk_loc[2]      MachineCtrl: 6 DFFP
//
// Выход инвертора — «обратный клок» генератора, т. е. прямой Clk машины
// (нарастающий фронт — рабочий). DFFP берёт его на C напрямую, DFF_J2N16
// (по спаду) — через свой инвертор в блоке (dfflibmap + opt_merge, один
// на блок). Все изменения тактовой цепи — только здесь: платы отличаются
// числом приёмников, а не схемой. Инверторы стоят по имени (NOT_N16
// в синтезе остаётся ячейкой, ABC её не сливает).
//======================================================================

`default_nettype none

module ClkTree #(
    parameter int N_LOC = 3     // местные инверторы MachineCtrl
)(
    input  wire             clk,       // Clk на плате: генератор или внешний вход
    output wire             clk_ip,
    output wire             clk_ap,
    output wire             clk_ipm,   // своя цепь у каждой памяти
    output wire             clk_apm,
    output wire [N_LOC-1:0] clk_loc
);
    wire clk_gen_n;

    NOT_N16 clkGen (.A (clk),       .Y (clk_gen_n));
    NOT_N16 clkIp  (.A (clk_gen_n), .Y (clk_ip));
    NOT_N16 clkAp  (.A (clk_gen_n), .Y (clk_ap));
    NOT_N16 clkIpm (.A (clk_gen_n), .Y (clk_ipm));
    NOT_N16 clkApm (.A (clk_gen_n), .Y (clk_apm));
    NOT_N16 clkLoc [N_LOC-1:0] (.A ({N_LOC{clk_gen_n}}), .Y (clk_loc));
endmodule

`default_nettype wire
