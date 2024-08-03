module consul(
    input wire Clk,
    input wire Rst_n,
    input wire [7:0] stdout,
    output wire [7:0] stdin,

    input wire [15:0] regs_in,
    output reg [9:0] regs_out,
    input wire Cout,
    input wire CinReq,
    output wire CioAcq
);

/* Consul 260 section */

//Output lines
wire [7:0] consul_out;//21L-27L
wire consul_sync;//28L
wire consul_set_tab;//21R
wire consul_set_kb_block;//22R

//Input lines
reg [7:0] consul_in;//11L-18L
reg consul_need_nl;//11R
reg consul_block_print;//12R
reg consul_is_moving;//13R
reg consul_high_reg;//14R
reg consul_coAcq;//15R
reg consul_red_print;//16R
reg consul_top_symbol_correction;//17R
reg consul_reg_signal;//18R

always @(posedge Clk) begin
    if (~Rst_n) begin
        regs_out <= 10'b0;
        {
            consul_reg_signal,
            consul_top_symbol_correction,
            consul_red_print,
            consul_coAcq,
            consul_high_reg,
            consul_is_moving,
            consul_block_print,
            consul_need_nl,
            consul_in[7:0]
        } <= 16'b0;
    end
    else begin
        regs_out[9:0] <= {
        consul_set_kb_block,
        consul_set_tab,
        consul_out[7:0]
        };
        {
            consul_reg_signal,
            consul_top_symbol_correction,
            consul_red_print,
            consul_coAcq,
            consul_high_reg,
            consul_is_moving,
            consul_block_print,
            consul_need_nl,
            consul_in[7:0]
        } <= regs_in;
    end
end

wire consul_in_is_valid = consul_in[7] & (^consul_in[6:0]);


endmodule
