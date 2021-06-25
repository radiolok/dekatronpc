module Ms6205(
    input wire Rst_n,
    input wire Clk,
    output reg [7:0] address,
    output wire [7:0] data,
    input wire write_addr,
    input wire write_data,
    output wire marker,
    input wire ready,
    input wire key_ms6205_iram,
    input wire key_ms6205_dram,
    input wire key_ms6205_cin,
    input wire key_ms6205_cout,
    output reg [1:0] ms6205_currentView

);

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter WIDTH = 8;

reg [7:0] data_n;

assign data[6:0] = {1'b0, ~data_n[6:0]};

 assign marker = 1'b0;

reg [1:0] ms6205_nextView;

parameter [1:0] 
    MS6205_IRAM = 2'b00,
    MS6205_DRAM = 2'b01,
    MS6205_CIN = 2'b10,
    MS6205_COUT = 2'b11;

always @(*) begin
        if (key_ms6205_iram)
            ms6205_nextView = MS6205_IRAM;
        else if (key_ms6205_dram)
            ms6205_nextView = MS6205_DRAM;
        else if (key_ms6205_cin)
            ms6205_nextView = MS6205_CIN;
        else if (key_ms6205_cout)
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


always @(posedge Clk, negedge Rst_n) begin
    if (!Rst_n) begin
        address <= 8'h00;
        data_n <= 8'h20;
    end
    else begin
        address <= (address == 8'h20)? 0 : address  + 1;
        data_n <= (address[0])? 8'h41 : 8'h42;
    end



end

endmodule