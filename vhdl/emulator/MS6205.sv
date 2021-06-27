module Ms6205(
    input wire Rst_n,
    input wire Clk,
    output reg [7:0] address,
    output wire [7:0] data,
    input wire write_addr,
    input wire write_data,
    output wire marker,
    input wire ready,
    input wire [39:0] keysCurrentState,
    output reg [1:0] ms6205_currentView

);

`include "keyboard_keys.svh" 

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter WIDTH = 8;

reg [7:0] data_n;

assign data[7:0] = {1'b0, ~data_n[6:0]};

 assign marker = 1'b0;

reg [1:0] ms6205_nextView;

parameter [1:0] 
    MS6205_IRAM = 2'b00,
    MS6205_DRAM = 2'b01,
    MS6205_CIN = 2'b10,
    MS6205_COUT = 2'b11;

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

always @(posedge Clk, negedge Rst_n) begin
    if (!Rst_n)
        ms6205_currentView <= MS6205_IRAM;
    else begin
        ms6205_currentView <= ms6205_nextView;
    end
end

wire PressedKey;

//This mux  compress IP and LOOP data into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(1), 
.SEL_WIDTH(8)
)  muxCathode1
        (  .data({
            226'b0,
            keysCurrentState}),
            .sel(address[7:0]),
            .y(PressedKey)
        );

always @(posedge Clk, negedge Rst_n) begin
    if (!Rst_n) begin
        address <= 8'h00;
        data_n <= 8'h00;
    end
    else begin
        address <= (address == 8'h9F)? 0 : address  + 1;
        data_n <= (PressedKey)? 8'h7F : 8'h20;
    end



end

endmodule