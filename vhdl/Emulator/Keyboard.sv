module Keyboard(
    input wire Rst_n,
    input wire Clk,
    input [7:0] kbCol,
    input [6:0] kbRow,
    input write,
    input read,
    input clear,
    output wire [39:0] keysCurrentState,
    output wire [15:0] numericKey,
    output wire [7:0] symbol
);

`include "Emulator/KeyboardKeys.sv"

wire readClk;

assign readClk = Clk & read;

assign numericKey = {
    keysCurrentState[KEYBOARD_F_KEY],
    keysCurrentState[KEYBOARD_E_KEY],
    keysCurrentState[KEYBOARD_D_KEY],
    keysCurrentState[KEYBOARD_C_KEY],
    keysCurrentState[KEYBOARD_B_KEY],
    keysCurrentState[KEYBOARD_A_KEY],
    keysCurrentState[KEYBOARD_9_KEY],
    keysCurrentState[KEYBOARD_8_KEY],
    keysCurrentState[KEYBOARD_7_KEY],
    keysCurrentState[KEYBOARD_6_KEY],
    keysCurrentState[KEYBOARD_5_KEY],
    keysCurrentState[KEYBOARD_4_KEY],
    keysCurrentState[KEYBOARD_3_KEY],
    keysCurrentState[KEYBOARD_2_KEY],
    keysCurrentState[KEYBOARD_1_KEY],
    keysCurrentState[KEYBOARD_0_KEY]
};

KeyToSymbol keyToSymbol(
    .numericKey(numericKey),
    .symbol(symbol),
    .BFISA(currentIsa)
);

reg currentIsa;
reg nextIsa;

parameter 
    MaintainanceIsa = 1'b0,
    BrainfuckISA = 1'b1;

always @* begin
    if (keysCurrentState[KEYBOARD_F_KEY])
        nextIsa = BrainfuckISA;
    else if (keysCurrentState[KEYBOARD_E_KEY])
        nextIsa = MaintainanceIsa;
    else 
        nextIsa = currentIsa;
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n)
        currentIsa <= BrainfuckISA;
    else 
        currentIsa <= nextIsa;
end

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

