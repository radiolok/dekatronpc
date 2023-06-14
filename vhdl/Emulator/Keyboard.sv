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

KeyToSymbol keyToSymbol(
    .numericKey(numericKey),
    .symbol(symbol),
    .BFISA(currentIsa)
);

reg currentIsa;
reg nextIsa;


always_comb begin
    if (keysCurrentState[KEYBOARD_F_KEY])
        nextIsa = BRAINFUCK_ISA;
    else if (keysCurrentState[KEYBOARD_E_KEY])
        nextIsa = DEBUG_ISA;
    else 
        nextIsa = currentIsa;
end

always @(negedge Clk, negedge Rst_n) begin
    if (~Rst_n)
        currentIsa <= BRAINFUCK_ISA;
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

