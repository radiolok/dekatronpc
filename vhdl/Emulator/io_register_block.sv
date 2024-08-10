module io_register_block #(
    parameter BOARDS = 16,
    parameter INSTALLED_BOARDS = 2
)
(
    output wire [3:0] io_address,
    output wire [1:0] io_enable_n,
    inout wire [7:0] io_data,
    input wire Clk,
    input wire Rst_n,
    input wire [BOARDS*8-1:0] outputs,
    output wire [BOARDS*8-1:0] inputs
);

wire [4:0] channel_num; 

UpCounter #(.TOP(INSTALLED_BOARDS*2-1),
            .WIDTH(5)) 
            ioChannelsCounter(
            .Tick(Clk),
            .Rst_n(Rst_n),
            .Count(channel_num));

assign io_address = {channel_num[0], channel_num[3:1]};

wire en_1_n = channel_num[4];
wire en_2_n = ~channel_num[4];

assign io_enable_n = {en_2_n, en_1_n};

reg [7:0] current_out_reg;

wire [3:0] reg_num = {channel_num[4:1]};

wire WriteReg = channel_num[0];

bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(4)
)  muxIOOutRegs
    (  .data(outputs),
        .sel(reg_num),
        .y(current_out_reg)
    );

assign io_data  = WriteReg ? current_out_reg : 8'hz; 

input_regs #(
    .BOARDS(BOARDS)
) inputRegs(
    .Clk(Clk),
    .ReadEnable(~WriteReg),
    .data(io_data),
    .outputs(inputs),
    .reg_num(reg_num)
);

endmodule
