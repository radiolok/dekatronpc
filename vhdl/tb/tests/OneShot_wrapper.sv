// Wrapper for OneShot module to avoid name collision in cocotb
module OneShot_test_wrapper #(
    parameter DELAY = 1
)(
    input Clk,
    input En,
    input Rst_n,
    output wire pulse_out
);
    OneShot #(.DELAY(DELAY)) uut(
        .Clk(Clk),
        .En(En),
        .Rst_n(Rst_n),
        .Impulse(pulse_out)
    );
endmodule
