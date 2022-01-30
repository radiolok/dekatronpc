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
    output reg [2:0] ms6205_currentView
);

`include "keyboard_keys.sv" 

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter WIDTH = 8;

parameter [2:0] 
    MS6205_RESTART = 3'b000,
    MS6205_IRAM = 3'b001,
    MS6205_DRAM = 3'b010,
    MS6205_CIN = 3'b011,
    MS6205_COUT = 3'b100;

reg [7:0] data_n;

assign data[7:0] = {1'b0, ~data_n[6:0]};

reg [2:0] ms6205_nextView;

assign marker = (ms6205_currentView == MS6205_IRAM) & (DPC_State == 2);

always @(*) begin
    if (ms6205_currentView == MS6205_RESTART) begin
        ms6205_nextView = (address < 'd160)? MS6205_RESTART : MS6205_IRAM;
    end
    else begin
        if (keysCurrentState[KEYBOARD_IRAM_KEY])
            ms6205_nextView = MS6205_IRAM;
        else if (keysCurrentState[KEYBOARD_DRAM_KEY])
            ms6205_nextView = MS6205_DRAM;
        else if (keysCurrentState[KEYBOARD_CIN_KEY])
            ms6205_nextView = MS6205_CIN;
        else if (keysCurrentState[KEYBOARD_COUT_KEY])
            ms6205_nextView = MS6205_COUT;
        else if (keysCurrentState[KEYBOARD_HARD_RST])
            ms6205_nextView = MS6205_RESTART;
        else
            ms6205_nextView = ms6205_currentView;
    end
end

always @(posedge Clock_1ms, negedge Rst_n) begin
    if (!Rst_n)
        ms6205_currentView <= MS6205_RESTART;
    else begin
        ms6205_currentView <= ms6205_nextView;
    end
end

reg [7:0] lastAddress;
reg [7:0] lastSymbol;

wire PressedKey;

assign PressedKey = symbol[7] | symbol[6] | symbol[5] | symbol[4] | symbol[3] | symbol[2] | symbol[1] | symbol[0];

always @(posedge Clock_1ms, negedge Rst_n) begin
    if (!Rst_n) begin
        address <= 8'h00;
        lastAddress <= 8'h00;
        data_n <= 8'h00;
        lastSymbol <= 0;
        ms6205_addr_acq <= 1'b1;
        ms6205_data_acq <= 1'b1;
    end
    else begin
        if (ms6205_currentView == MS6205_RESTART) begin
            address <= address  + 1;
            data_n <= 'h20;
        end
        else begin            
            lastAddress <= address;
            address <= ipAddress;
            data_n <= (PressedKey)? symbol : 8'h20;
            lastSymbol <= data_n;
        end        
    end
end

endmodule