`define MODELSIM_MODE;

module tb;


reg Clk;
wire ms6205_write_addr_n;
wire ms6205_write_data_n;
wire in12_write_anode;
wire in12_write_cathode;
wire in12_clear;
wire keyboard_write;
wire keyboard_clear;
wire [7:0] emulData;

wire [1:0] KEYS;

reg Rst_n;

assign KEYS = {1'b0, Rst_n};

Emulator #(
    .DIVIDE_TO_1US(28'd2),
    .DIVIDE_TO_1MS(28'd40),
    .DIVIDE_TO_1S(28'd20)
    )Emulator(
    .FPGA_CLK_50(Clk),
    .ms6205_write_addr_n(ms6205_write_addr_n),
    .ms6205_write_data_n(ms6205_write_data_n), 
    .in12_write_anode(in12_write_anode),
    .in12_write_cathode(in12_write_cathode),
    .in12_clear(in12_clear),
    .keyboard_write(keyboard_write),
    .keyboard_clear(keyboard_clear),
    .emulData(emulData),
    .KEY(KEYS)
);

initial begin
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial
begin
    Rst_n <= 1'b1;
	#10
	Rst_n <= 1'b0;
	#10
	Rst_n <= 1'b1;
end

endmodule