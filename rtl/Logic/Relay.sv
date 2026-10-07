// Relay logic for the panel switches.
//
// A logic function of a static panel switch costs tubes with filaments
// burning all the time, while the switch changes only by hand. A relay does
// the same job with no filament. Only 2CO relays are used (two changeover
// contacts, one coil): RELAY_2CO, Cn = COIL ? NOn : NCn.
//
// RULE: a relay coil (sel/en below) is driven ONLY by a panel switch. A relay
// switches in milliseconds and wears out; it must never sit in clocked or
// otherwise fast logic. The contacts are passive, so the data inputs may be
// any signal, fast ones included.
//
// RelayMux and RelayEn are kept as separate modules (keep_hierarchy): the
// synthesis flow must not flatten them, the RELAY_2CO cells stay where RTL
// put them and are counted as relays, not tubes (rtl/vtube/vtube_cells.lib).

`ifndef SYNTH
// Model of the relay. In synthesis the cell comes from vtube_cells.lib.
module RELAY_2CO (
    input  wire COIL,
    input  wire NC1,
    input  wire NO1,
    input  wire NC2,
    input  wire NO2,
    output wire C1,
    output wire C2
);
    assign C1 = COIL ? NO1 : NC1;
    assign C2 = COIL ? NO2 : NC2;
endmodule
`endif

// 2**S to 1 multiplexer of W-bit words, selected by S switches.
// Word i is d[i*W +: W]; y = word sel. Built as a tree of changeover
// contacts: select bit l switches 2**(S-1-l)*W contacts, packed two per relay.
// Relays: sum over l of ceil(2**(S-1-l)*W / 2).
(* keep_hierarchy = "yes" *)
module RelayMux #(
    parameter W = 1,
    parameter S = 1
)(
    input  wire [S-1:0]        sel,
    input  wire [(2**S)*W-1:0] d,
    output wire [W-1:0]        y
);
    // Level l switches 2**(S-l) words (i) down to 2**(S-1-l) words (o).
    // One vector per level: a single array for all levels would be a false
    // combinational loop for Verilator (UNOPTFLAT).
    genvar l, r;
    generate
        for (l = 0; l < S; l = l + 1) begin : g_lvl
            localparam P = (2**(S-1-l)) * W;   // contacts on this level
            wire [2*P-1:0] i;
            wire [P-1:0]   o;
            if (l == 0) begin : g_d
                assign i = d;
            end
            else begin : g_prev
                assign i = g_lvl[l-1].o;
            end
            for (r = 0; r < (P+1)/2; r = r + 1) begin : g_rel
                // contact p: word p/W, bit p%W; NC = even word, NO = odd word
                localparam P1 = 2*r;
                localparam P2 = 2*r + 1;
                if (P2 < P) begin : g_two
                    RELAY_2CO rel (
                        .COIL (sel[l]),
                        .NC1  (i[(2*(P1/W))*W   + P1%W]),
                        .NO1  (i[(2*(P1/W)+1)*W + P1%W]),
                        .NC2  (i[(2*(P2/W))*W   + P2%W]),
                        .NO2  (i[(2*(P2/W)+1)*W + P2%W]),
                        .C1   (o[P1]),
                        .C2   (o[P2])
                    );
                end
                else begin : g_one
                    /* verilator lint_off UNUSEDSIGNAL */
                    wire spare;   // second contact unused
                    /* verilator lint_on UNUSEDSIGNAL */
                    RELAY_2CO rel (
                        .COIL (sel[l]),
                        .NC1  (i[(2*(P1/W))*W   + P1%W]),
                        .NO1  (i[(2*(P1/W)+1)*W + P1%W]),
                        .NC2  (1'b0),
                        .NO2  (1'b0),
                        .C1   (o[P1]),
                        .C2   (spare)
                    );
                end
            end
        end
    endgenerate

    assign y = g_lvl[S-1].o;
endmodule

// W-bit enable: y = en ? a : 0. The normally closed contacts go to logic 0.
// Relays: ceil(W / 2).
(* keep_hierarchy = "yes" *)
module RelayEn #(
    parameter W = 1
)(
    input  wire         en,
    input  wire [W-1:0] a,
    output wire [W-1:0] y
);
    genvar r;
    generate
        for (r = 0; r < (W+1)/2; r = r + 1) begin : g_rel
            if (2*r + 1 < W) begin : g_two
                RELAY_2CO rel (
                    .COIL (en),
                    .NC1  (1'b0),
                    .NO1  (a[2*r]),
                    .NC2  (1'b0),
                    .NO2  (a[2*r+1]),
                    .C1   (y[2*r]),
                    .C2   (y[2*r+1])
                );
            end
            else begin : g_one
                /* verilator lint_off UNUSEDSIGNAL */
                wire spare;   // second contact unused
                /* verilator lint_on UNUSEDSIGNAL */
                RELAY_2CO rel (
                    .COIL (en),
                    .NC1  (1'b0),
                    .NO1  (a[2*r]),
                    .NC2  (1'b0),
                    .NO2  (1'b0),
                    .C1   (y[2*r]),
                    .C2   (spare)
                );
            end
        end
    endgenerate
endmodule
