module consul(
    input wire Clk,
    input wire Rst_n,
    input wire [7:0] print_data_i,
    output reg [7:0] kb_data_o,

    input wire [15:0] regs_in,
    output reg [9:0] regs_out,
    input wire print_data_vld,
    output reg kb_data_vld,
    output reg print_data_rdy
);

/* Consul 260 section */

//Output lines
reg [6:0] out;//21L-27L
reg sync;//28L
reg set_tab;//21R
reg set_kb_block;//22R

//Input lines
reg [7:0] in;//11L-18L
reg need_nl;//11R
reg block_print;//12R
reg is_moving;//13R
reg high_reg;//14R
reg coAcq;//15R
/* verilator lint_off UNUSEDSIGNAL */
reg red_print;//16R
wire dummy_stdout = print_data_i[7];
/* verilator lint_on UNUSEDSIGNAL */
reg top_symbol_correction;//17R
reg cin_ready;//18R

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

wire in_is_valid = in[7] & (^in[6:0]);

parameter [3:0]
    IDLE        = 4'b0000,
    WAIT_IN     = 4'b0001,
    SET_CODE    = 4'b0010,
    SET_SYNC    = 4'b0011,
    WAIT_OUT    = 4'b0100,
    WAIT_REG    = 4'b0101;

reg NL_workout;
reg REG_switch;

reg [3:0] state;

reg [3:0] high_reg_counter;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        state <= 4'b0;
        kb_data_o <= 8'b0;
        kb_data_vld <= 1'b0;
        sync <= 1'b0;
        set_kb_block <= 1'b1;
        print_data_rdy <= 1'b0;
        set_tab <= 1'b0;
        NL_workout <= 1'b0;
        high_reg_counter <= 4'b0000;
    end
    else begin
        if (high_reg_counter > 0) begin
            high_reg_counter <= high_reg_counter - 4'b0001;
        end
        case(state)
        IDLE: begin
            if (print_data_vld) begin
                if (~is_moving & ~block_print) begin
                    if (need_nl) begin
                        out <= 7'h0d;//CR
                        NL_workout <= 1'b1;
                    end
                    else begin
                        if (high_reg ^ ~print_data_i[5]) begin
                            REG_switch <= 1'b1;
                            high_reg_counter <= 4'd11;
                            out <= {6'b000111, print_data_i[5]};
                        end else begin
                            out <= print_data_i[6:0];
                            NL_workout <= 1'b0;
                            REG_switch <= 1'b0;
                        end
                    end
                    state <= SET_CODE;
                end
            end else begin
                    state <= IDLE;
                    print_data_rdy <= 1'b0;
            end       
        end
        WAIT_IN: begin
            if (cin_ready & in_is_valid) begin
                kb_data_o <= {top_symbol_correction, in[6:0]};
            end
        end
        SET_CODE: begin//10ms delay for relays
            state <= SET_SYNC;
        end
        SET_SYNC: begin
            sync <= 1'b1;
            state <= (REG_switch)? WAIT_REG : WAIT_OUT;
        end
        WAIT_REG: begin
            if (high_reg_counter == 0) begin
                REG_switch <= 1'b0;
                sync <= 1'b0;
                state <= IDLE;
            end
        end
        WAIT_OUT: begin
            if (NL_workout & ~is_moving) begin
                sync <= 1'b0;
                state <= IDLE;
                NL_workout <= 1'b0;
            end
            else begin
                if (coAcq) begin
                    sync <= 1'b0;
                    state <= IDLE;
                    print_data_rdy <= 1'b1;
                end
            end
        end
        default:
            state <= IDLE;
        endcase
    end
end

endmodule
