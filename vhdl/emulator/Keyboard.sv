`define KEYBOARD_IRAM_KEY 0
`define KEYBOARD_DRAM_KEY 1
`define KEYBOARD_CIN_KEY 2
`define KEYBOARD_COUT_KEY 3


module Keyboard(
    input wire Rst_n,
    input wire Clk,
    input [7:0] kbCol,
    input [6:0] kbRow,
    input write,
    input read,
    input clear,
    output wire [39:0] keysCurrentState
);

wire readClk;

assign readClk = Clk & read;

RegisterFileFlatOut #(
    .WIDTH(5),
    .HEIGHT(8)
) keyboardStates(
    .Rst_n(Rst_n),
    .En(readClk),    
    .In(kbRow[4:0]),
    .Cs(kbCol),
    .Out(keysCurrentState)
) ;



endmodule