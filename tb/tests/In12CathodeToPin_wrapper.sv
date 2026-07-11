module In12CathodeToPin_wrapper(
    input wire [3:0] Cathode,
    output wire [3:0] Pin
);
    assign Pin = In12CathodeToPin(Cathode);
endmodule
