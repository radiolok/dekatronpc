//======================================================================
// WriteLineDec — дешифратор записи по катодным линиям [TRS v0.56]
//----------------------------------------------------------------------
// Строит уровни линий W0…W9 одной декады с полной записью (плата
// каналов записи, sch/logic/DEKATRON_A110/README.md §3.3):
//
//   открыта_k = ¬W ∨ sel_k,  W = Set ∨ Zero ∨ Top
//   sel_k     = Set·(In = k) ∨ Zero·(k = 0) ∨ Top·(k = TOP_POS)
//
// В покое все линии 1 (каналы открыты), при записи открыта только линия
// цели: линия горящего катода закрывается, разряд переходит на неё.
// Сброс в 0 и в TOP — та же запись. In_n — тетрада активным нулём
// (TC-O3), коды 10–15 безразличны.
//
// Собран вручную из ячеек библиотеки (владелец, 2026-11-07,
// doc/cathode_line_write.md §3): ABC на этой функции давал 35,5 лампы на
// декаду, ручная схема — 27.
//
//   Пары разрядов: A = (b1, b0) — 4 линии j, B = (b3, b2) — 00, 01, 1x.
//   Цифра k — пересечение одной линии A и одной линии B (8 = 1x·00,
//   9 = 1x·01, коды 10–15 безразличны).
//   Линия «закрыть при записи»: Xa_j = Set ∧ ¬(b1b0 = j)
//     = A1OOI(l1, l0, ¬Set); Xb_1x = Set ∧ ¬b3 = NOR2(¬Set, b3).
//   Линия «закрыть при сбросе» R_k (общая для декад счётчика): K0 — Top,
//   K_TOP — Zero, остальные — Zero ∨ Top.
//   Выход: открыта_k = NOR3(Xa_j, Xb_i, R_k).
//
// При MAX_DIGIT ≤ 3 (сотни Data, TC-N1) старшая пара не нужна: коды выше
// MAX_DIGIT безразличны, выход — NOR2(Xa_j, R_k).
//======================================================================

`default_nettype none

module WriteLineDec #(
    parameter bit      TOP_EN    = 1'b0,   // есть сброс в TOP
    parameter unsigned TOP_POS   = 9,      // позиция TOP
    parameter unsigned MAX_DIGIT = 9       // выше — линий нет (TC-N1)
)(
    // При MAX_DIGIT ≤ 3 старшая пара не используется (TC-N1)
/* verilator lint_off UNUSEDSIGNAL */
    input  wire [3:0] In_n,
/* verilator lint_on UNUSEDSIGNAL */
    input  wire       Set,
    input  wire       Zero,
    input  wire       Top,
    output wire [9:0] LineOpen
);
    localparam bit USE_B = (MAX_DIGIT > 3);

    // Общие для декад счётчика линии: после разворачивания иерархии ABC
    // сливает их у всех экземпляров
    wire set_n = ~Set;
    wire top   = TOP_EN & Top;
    wire zt    = Zero | top;

    // Прямые литералы (In_n — инверсные). Ставятся только нужные
/* verilator lint_off UNUSEDSIGNAL */
    wire [3:0] b;
/* verilator lint_on UNUSEDSIGNAL */
    genvar n;
    generate
        for (n = 0; n < 4; n++) begin : g_lit
            if ((n < 2) || (USE_B && n == 2) || (USE_B && MAX_DIGIT >= 8 && n == 3)) begin : g_not
                NOT_N16 lit (.A (In_n[n]), .Y (b[n]));
            end
            else begin : g_none
                assign b[n] = 1'b0;   // не используется
            end
        end
    endgenerate

    // Пара A = (b1, b0): Xa_j = Set ∧ ¬(b1b0 = j)
    wire [3:0] xa;
    generate
        for (n = 0; n < 4; n++) begin : g_xa
            if (n <= int'(MAX_DIGIT)) begin : g_on
                A1OOI_N16J2 xaGate (
                    .A (((n / 2) % 2 == 1) ? b[1] : In_n[1]),
                    .B ((n % 2 == 1)       ? b[0] : In_n[0]),
                    .C (set_n),
                    .Y (xa[n])
                );
            end
            else begin : g_off
                assign xa[n] = 1'b0;
            end
        end
    endgenerate

    // Пара B = (b3, b2): 00, 01, 1x
/* verilator lint_off UNUSEDSIGNAL */
    wire [2:0] xb;
/* verilator lint_on UNUSEDSIGNAL */
    generate
        if (USE_B) begin : g_xb
            A1OOI_N16J2 xb00 (.A (In_n[3]), .B (In_n[2]), .C (set_n), .Y (xb[0]));
            A1OOI_N16J2 xb01 (.A (In_n[3]), .B (b[2]),     .C (set_n), .Y (xb[1]));
            if (MAX_DIGIT >= 8) begin : g_1x
                NOR2_N16 xb1x (.A (set_n), .B (b[3]), .Y (xb[2]));
            end
            else begin : g_no_1x
                assign xb[2] = 1'b0;
            end
        end
        else begin : g_no_xb
            assign xb = 3'b0;
        end
    endgenerate

    // Выходы
    generate
        for (n = 0; n < 10; n++) begin : g_out
            if (n > int'(MAX_DIGIT)) begin : g_none
                assign LineOpen[n] = 1'b0;
            end
            else begin : g_on
                // Пара A и пара B цифры n
                localparam int unsigned JA = (n >= 8) ? (n - 8) : (n % 4);
                localparam int unsigned IB = (n >= 8) ? 2 : (n / 4);
                wire r = (n == 0)                         ? top  :
                         (TOP_EN && n == int'(TOP_POS))   ? Zero : zt;
                if (USE_B) begin : g_nor3
                    NOR3_N16 outGate (.A (xa[JA]), .B (xb[IB]), .C (r),
                                      .Y (LineOpen[n]));
                end
                else begin : g_nor2
                    NOR2_N16 outGate (.A (xa[JA]), .B (r), .Y (LineOpen[n]));
                end
            end
        end
    endgenerate

`ifndef SYNTH
    initial
        if (MAX_DIGIT > 9 || TOP_POS > MAX_DIGIT || (TOP_EN && TOP_POS == 0))
            $error("WriteLineDec: MAX_DIGIT (%0d) must be 0..9 and cover TOP_POS (%0d)",
                   MAX_DIGIT, TOP_POS);
`endif
endmodule

`default_nettype wire
