module Ms6205(
    input wire Rst_n,
    input wire Clock_1ms,
    output reg ms6205_addr_acq,
	output reg ms6205_data_acq,
    input wire [7:0] ipAddress,
    input wire [7:0] symbol,
    output reg [7:0] address,
    output wire [7:0] data,
    input wire write_addr,
    input wire write_data,
    output wire marker,
    input wire ready,
    input wire [39:0] keysCurrentState,
    input wire [2:0] DPC_State,
    output reg [1:0] ms6205_currentView

);

`include "keyboard_keys.sv" 

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter WIDTH = 8;

parameter [1:0] 
    MS6205_IRAM = 2'b00,
    MS6205_DRAM = 2'b01,
    MS6205_CIN = 2'b10,
    MS6205_COUT = 2'b11;

reg [7:0] data_n;

assign data[7:0] = {1'b0, ~data_n[6:0]};

reg [1:0] ms6205_nextView;

assign marker = (ms6205_currentView == MS6205_IRAM) & (DPC_State == 2);

always @(*) begin
        if (keysCurrentState[KEYBOARD_IRAM_KEY])
            ms6205_nextView = MS6205_IRAM;
        else if (keysCurrentState[KEYBOARD_DRAM_KEY])
            ms6205_nextView = MS6205_DRAM;
        else if (keysCurrentState[KEYBOARD_CIN_KEY])
            ms6205_nextView = MS6205_CIN;
        else if (keysCurrentState[KEYBOARD_COUT_KEY])
            ms6205_nextView = MS6205_COUT;
        else
            ms6205_nextView = ms6205_currentView;
end

always @(posedge Clock_1ms, negedge Rst_n) begin
    if (!Rst_n)
        ms6205_currentView <= MS6205_IRAM;
    else begin
        ms6205_currentView <= ms6205_nextView;
    end
end

reg [7:0] lastAddress;

wire PressedKey;

assign PressedKey = symbol[7] | symbol[6] | symbol[5] | symbol[4] | symbol[3] | symbol[2] | symbol[1] | symbol[0];

always @(posedge Clock_1ms, negedge Rst_n) begin
    if (!Rst_n) begin
        address <= 8'h00;
        lastAddress <= 8'h00;
        data_n <= 8'h00;
        ms6205_addr_acq <= 1'b1;
        ms6205_data_acq <= 1'b1;
    end
    else begin
        lastAddress <= address;
        address <= ipAddress;
        data_n <= (PressedKey)? symbol : 8'h20;
    end



end

endmodule