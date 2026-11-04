module Keyboard(
    input wire Rst_n,
    input wire Clk,
    input [7:0] kbCol,
    /* verilator lint_off UNUSEDSIGNAL */
    input [6:0] kbRow,//6-5 not used
    /* verilator lint_on UNUSEDSIGNAL */
    input read,
    /* verilator lint_off UNUSEDSIGNAL */
    input write,
    input clear,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [39:0] keysCurrentState,
    output wire [15:0] numericKey,
    output wire [7:0] symbol
);

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

// ISA16: one instruction set, the hex key is the opcode (doc/isa16.md)
assign symbol = (|numericKey)? OpcodeToSymbol(BinaryToHex(numericKey)) : 8'h0;

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

