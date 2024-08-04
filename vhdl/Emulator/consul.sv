module consul(
    input wire Clk,
    input wire Rst_n,
    input wire [7:0] stdout,
    output reg [7:0] stdin,

    input wire [15:0] regs_in,
    output reg [9:0] regs_out,
    input wire Cout,
    input wire CinReq,
    output wire CioAcq
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
wire dummy_stdout = stdout[7];
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
    WAIT_OUT    = 4'b0100;

reg NL_workout;
reg REG_switch;

reg [3:0] state;
always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        state <= 4'b0;
        stdin <= 8'b0;
        sync <= 1'b0;
        set_kb_block <= 1'b1;
        CioAcq <= 1'b0;
        set_tab <= 1'b0;
        NL_workout <= 1'b0;
    end
    else begin
        case(state)
        IDLE: begin
            if (CinReq) begin
                state <=  WAIT_IN;
                set_kb_block <= 1'b0;
            end
            if (Cout) begin
                if (~is_moving | ~block_print) begin
                    if (need_nl) begin
                        out <= 7'h0d;//CR
                        NL_workout <= 1'b1;
                    end
                    else begin
                        if (high_reg ^ stdout[7]) begin
                            REG_switch <= 1'b1;
                            out <= {6'b000111, stdout[7]};
                        end else begin
                            out <= stdout[6:0];
                            NL_workout <= 1'b0;
                            REG_switch <= 1'b0;
                        end
                    end
                    state <= SET_CODE;
                end
            end
            if (~CinReq & ~Cout) begin
                state <= IDLE;
                CioAcq <= 1'b0;
            end
        end
        WAIT_IN: begin
            if (cin_ready & in_is_valid) begin
                stdin <= {top_symbol_correction, in[6:0]};
            end
        end
        SET_CODE: begin//10ms delay for relays
            state <= SET_SYNC;
        end
        SET_SYNC: begin
            sync <= 1'b1;
            state <= WAIT_OUT;
        end
        WAIT_OUT: begin
            if (NL_workout & ~is_moving) begin
                sync <= 1'b0;
                state <= IDLE;
                NL_workout <= 1'b0;
            end
            else begin
                if (REG_switch & ~(high_reg ^ stdout[7])) begin
                    REG_switch <= 1'b0;
                    sync <= 1'b0;
                    state <= IDLE;
                end else begin
                    if (coAcq) begin
                        sync <= 1'b0;
                        state <= IDLE;
                        CioAcq <= 1'b1;
                    end
                end
            end
        end
        default:
            state <= IDLE;
        endcase
    end
end

endmodule
