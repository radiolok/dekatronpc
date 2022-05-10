module io_register_block #(
    parameter BOARDS = 16,
    parameter INSTALLED_BOARDS = 2
)
(
    output wire [3:0] io_address,
    output wire [1:0] io_enable,
    inout [7:0] io_data,
    input wire Clk,
    input wire Rst_n,
    input wire [BOARDS*8-1:0] outputs,
    output wire [BOARDS*8-1:0] inputs
);

wire [4:0] count_num;

UpCounter #(.TOP(INSTALLED_BOARDS*2),
            .WIDTH(5)) 
            ioBoardsCounter(
            .Tick(Clk),
            .Rst_n(Rst_n),
            .Count(count_num));

wire [3:0] reg_num = {count_num[4:1]};

wire WriteClock = count_num[0];

assign io_address = {WriteClock, reg_num[2:0]};
assign io_enable = {reg_num[3], ~reg_num[3]};

wire [7:0] current_out_reg;

bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(4)
)  muxIOOutRegs
        (  .data(outputs),
            .sel(reg_num),
            .y(current_out_reg)
        );

assign io_data  = WriteClock ? 8'hz : current_out_reg; 

input_regs inputRegs(
    .Clk(Clk),
    .ReadStrobe(~WriteClock),
    .data(io_data),
    .outputs(inputs),
    .reg_num(reg_num)
);

endmodule

module input_regs #(
    parameter BOARDS = 16
)(
    input wire [3:0] reg_num,
    input wire ReadStrobe,
    input wire Clk,
    input wire [7:0] data,
    output wire [BOARDS*8-1:0] outputs
);

reg [7:0] regs [0:BOARDS-1];

always_comb begin 
    outputs = { regs[15],  regs[14],  regs[13],  regs[12],  
                regs[11],  regs[10],  regs[9],   regs[8],   
                regs[7],   regs[6],   regs[5],   regs[4],   
                regs[3],   regs[2],   regs[1],   regs[0]};    
end

always @(posedge Clk) begin
    if (ReadStrobe)
        regs[reg_num] <= data;
end

endmodule

