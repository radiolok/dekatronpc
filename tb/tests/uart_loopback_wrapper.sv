// UART loopback wrapper: connects TX output directly to RX input
// for end-to-end loopback testing.
module uart_loopback_wrapper (
    input clk,
    input rst,
    input i_vld,
    input [7:0] i_data,
    output o_rdy,
    output rx_o_vld,
    output rx_pc_pass,
    output [7:0] rx_o_data
);

    wire tx_out;

    uart_tx #(
        .DATA_WIDTH(8),
        .PARITY_CHECK("NONE"),
        .CLK_FREQ(50000000),
        .STOP_BITS(1),
        .BAUD_RATE(9600)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .i_vld(i_vld),
        .i_data(i_data),
        .o_rdy(o_rdy),
        .tx(tx_out)
    );

    uart_rx #(
        .DATA_WIDTH(8),
        .PARITY_CHECK("NONE"),
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) u_rx (
        .clk(clk),
        .rst(rst),
        .rx(tx_out),
        .i_rdy(1'b1),
        .o_vld(rx_o_vld),
        .pc_pass(rx_pc_pass),
        .o_data(rx_o_data)
    );

endmodule
