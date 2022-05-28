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

wire en_1_n = ~(~Clk & ~channel_num[4]);
wire en_2_n = ~(~Clk & channel_num[4]);

assign io_enable_n = {en_1_n, en_1_n};

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

module input_regs #(
    parameter BOARDS = 16
)(
    input wire [3:0] reg_num,
    input wire ReadEnable,
    input wire Clk,
    input wire [7:0] data,
    output wire [BOARDS*8-1:0] outputs
);

reg [7:0] regs [0:BOARDS-1];


assign  outputs = { regs[15],  regs[14],  regs[13],  regs[12],  
                regs[11],  regs[10],  regs[9],   regs[8],   
                regs[7],   regs[6],   regs[5],   regs[4], 
                regs[3],   regs[2],   regs[1],   regs[0]};    


always @(posedge Clk) begin
    if (ReadEnable)
        regs[reg_num] <= data;
end

endmodule

//Verilog module.
module segment7(
     input wire [3:0] hex,
     output wire [6:0] seg
    );

//always block for converting bcd digit into 7 segment format
    always @(hex)
    begin
        case (hex) //case statement
            0 : seg = 7'b0111111;
            1 : seg = 7'b0000110;
            2 : seg = 7'b1011011;
            3 : seg = 7'b1001111;
            4 : seg = 7'b1100110;
            5 : seg = 7'b1101101;
            6 : seg = 7'b1111101;
            7 : seg = 7'b0000111;
            8 : seg = 7'b1111111;
            9 : seg = 7'b1101111;
            4'hA: seg = 7'b1110111;
            4'hB: seg = 7'b1111100;
            4'hC: seg = 7'b0111001;
            4'hD: seg = 7'b1011110;
            4'hE: seg = 7'b1111001;
            4'hF: seg = 7'b1110001;
            //switch off 7 segment character when the bcd digit is not a decimal number.
            default : seg = 7'b0000000; 
        endcase
    end
    
endmodule

