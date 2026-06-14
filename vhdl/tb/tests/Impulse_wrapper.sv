// Wrapper for Impulse module to avoid name collision in cocotb
// The output wire is renamed from "Impulse" to "pulse_out"
module Impulse_test_wrapper(
    input Clk,
    input En,
    input Rst_n,
    output wire pulse_out
);
    Impulse uut(
        .Clk(Clk),
        .En(En),
        .Rst_n(Rst_n),
        .Impulse(pulse_out)
    );
endmodule
