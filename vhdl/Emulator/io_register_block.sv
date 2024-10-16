module io_register_block #(
    parameter BOARDS = 16,
    parameter INSTALLED_BOARDS = 2
)
(
    output wire [3:0] addr_o,
    output wire [1:0] enable_n_o,
    inout wire [7:0] data_io,
    input wire Clk,
    input wire Rst_n,
    input wire [BOARDS*8-1:0] regs_out_i,
    output wire [BOARDS*8-1:0] regs_in_o
);

logic [4:0] channel_num; 

assign addr_o = {channel_num[0], channel_num[3:1]};

logic strobe;
wire en_1_n = channel_num[4] & strobe;
wire en_2_n = (~channel_num[4]) & strobe;

assign enable_n_o = {en_2_n, en_1_n};

reg [7:0] current_out_reg;

wire [3:0] reg_num = {channel_num[4:1]};

wire WriteReg = channel_num[0];

bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(4)
)  muxIOOutRegs
    (  .data(regs_out_i),
        .sel(reg_num),
        .y(current_out_reg)
    );

assign data_io  = WriteReg ? current_out_reg : 8'hz; 

wire read_enable = ~WriteReg & strobe;

input_regs #(
    .BOARDS(BOARDS)
) inputRegs(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .ReadEnable(read_enable),
    .data(data_io),
    .outputs(regs_in_o),
    .reg_num(reg_num)
);

localparam NONE = 2'd0;
localparam ADDR = 2'd1;
localparam STROBE = 2'd2;

logic [1:0] state;
logic [1:0] next_state;

always_comb begin
    case (state) 
        ADDR: begin
            next_state = STROBE;
        end
        STROBE: begin
            next_state = NONE;
        end
        default: begin
            next_state = ADDR;
        end
    endcase
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        state <= NONE;
    end else begin
        state <= next_state;
    end
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        strobe <= 1'b0;
    end else begin
        case (state)
            ADDR: begin
                strobe <= 1'b1;
            end
            STROBE: begin
                strobe <= 1'b0;
            end
            default: begin
                strobe <= 1'b0;
                channel_num <= (channel_num < (INSTALLED_BOARDS * 2-1))? 
                                    channel_num + 1'b1 : 
                                    '0;
            end
        endcase
    end
end

endmodule
