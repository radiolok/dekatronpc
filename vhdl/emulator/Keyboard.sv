module Keyboard(
    input wire Rst_n,
    input wire Clk,
    input [7:0] kbCol,
    input [6:0] kbRow,
    input write,
    input read,
    input clear
);

wire [39:0] keysCurrentState;

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