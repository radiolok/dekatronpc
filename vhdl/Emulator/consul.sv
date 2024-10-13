module consul(
    input wire Clk,
    input wire Rst_n,
    input wire [7:0] print_data_i,
    output reg [7:0] kb_data_o,

    input wire [15:0] regs_in,
    output reg [9:0] regs_out,
    input wire print_data_vld,
    output reg kb_data_vld,
    output wire print_data_rdy
);

localparam PERIOD_SYMBOL = 5;
localparam PERIOD_NL = 500;
localparam PERIOD_COLOR = 12;
/* Consul 260 section */

//Output lines
reg [6:0] out;//21L-27L
reg sync;//28L
reg set_tab;//21R
reg set_kb_block;//22R

//Input lines
/* verilator lint_off UNUSEDSIGNAL */
reg [7:0] in;//11L-18L
/* verilator lint_on UNUSEDSIGNAL */
reg need_nl;//11R
reg block_print;//12R
reg is_moving;//13R
reg high_reg;//14R
/* verilator lint_off UNUSEDSIGNAL */
reg coAcq;//15R
reg red_print;//16R
wire dummy_stdout = print_data_i[7];
reg top_symbol_correction;//17R
reg cin_ready;//18R
/* verilator lint_on UNUSEDSIGNAL */


always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        regs_out <= 10'b0;
        {
            cin_ready,
            top_symbol_correction,
            red_print,
            coAcq,
            high_reg,
            is_moving,
            block_print,
            need_nl,
            in[7:0]
        } <= 16'b0;
    end
    else begin
        regs_out[9:0] <= {
        set_kb_block,
        set_tab,
        sync,
        out[6:0]
        };
        {
            cin_ready,
            top_symbol_correction,
            red_print,
            coAcq,
            high_reg,
            is_moving,
            block_print,
            need_nl,
            in[7:0]
        } <= regs_in;
    end
end

//wire in_is_valid = in[7] & (^in[6:0]);

parameter [3:0]
    IDLE        = 4'b0000,
    WAIT        = 4'b0001,
    SET_CODE    = 4'b0010,
    SET_SYNC    = 4'b0011;

assign print_data_rdy = (state == IDLE);

reg srv_symbol;

reg [3:0] state;

reg [$clog2(PERIOD_NL)-1:0] high_reg_counter;

reg [6:0] print_data;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        state <= 4'b0;
        kb_data_o <= 8'b0;
        kb_data_vld <= 1'b0;
        sync <= 1'b0;
        set_kb_block <= 1'b0;
        set_tab <= 1'b0;
        srv_symbol <= 1'b0;
        high_reg_counter <= '0;
    end
    else begin
        if (high_reg_counter > 0) begin
            high_reg_counter <= high_reg_counter - 1;
        end
        case(state)
            IDLE: begin
                if (print_data_vld) begin
                    print_data <= print_data_i[6:0];
                    state <= WAIT;
                end else begin
                    state <= IDLE;
                end
            end
            WAIT: begin
                if (~is_moving & ~block_print) begin
                    if (need_nl) begin
                        out <= 7'h0d;//CR
                        srv_symbol <= 1'b1;
                        high_reg_counter <= PERIOD_NL;
                    end
                    else begin
                        if (high_reg ^ ~print_data[5]) begin
                            high_reg_counter <= PERIOD_COLOR;
                            out <= {6'b000111, print_data[5]};
                            srv_symbol <= 1'b1;
                        end else begin
                            high_reg_counter <= PERIOD_SYMBOL;
                            out <= print_data[6:0];
                            srv_symbol <= 1'b0;
                        end
                    end
                    state <= SET_CODE;
                end else begin
                    state <= WAIT;
                end
            end
            SET_CODE: begin//10ms delay for relays
                sync <= 1'b1;
                state <= SET_SYNC;
            end
            SET_SYNC: begin
                if (high_reg_counter == 0) begin
                    sync <= 1'b0;
                    out <= '0;
                    state <= (srv_symbol)? WAIT : IDLE;
                end
            end
            default:
                state <= IDLE;
        endcase
    end
end

endmodule
