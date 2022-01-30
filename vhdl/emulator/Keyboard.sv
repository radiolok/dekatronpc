
module KeyToSymbol(
    input wire [15:0] numericKey,
    input wire BFISA,
    output reg [7:0] symbol
);

always_comb
  case(numericKey)
    16'b0000000000000001: symbol = 'h4E;                 //0 - N
    16'b0000000000000010: symbol = 'h48;                 //1 - H
    16'b0000000000000100: symbol =  'h2B;                 //2 +
    16'b0000000000001000: symbol = 'h2D;                 //3 -
    16'b0000000000010000: symbol = 'h3C;                 //4 <
    16'b0000000000100000: symbol = 'h3E;                 //5 >
    16'b0000000001000000: symbol = (BFISA) ? 8'h5B : 8'h28; //6 [ (
    16'b0000000010000000: symbol = (BFISA) ? 8'h5D : 8'h29; //7 ] )
    16'b0000000100000000: symbol = (BFISA) ? 8'h2E : 8'h4C; //8 . L
    16'b0000001000000000: symbol = (BFISA) ? 8'h2C : 8'h49; //9 , I
    16'b0000010000000000: symbol = 'h30;                 //A
    16'b0000100000000000: symbol = 'h40;                 //B
    16'b0001000000000000: symbol = 'h43;                 //C
    16'b0010000000000000: symbol = 'h44;                 //D 
    16'b0100000000000000: symbol = 'h4D;                 //E - M
    16'b1000000000000000: symbol = 'h42;                 //F - B
    default: symbol = 8'h00;
  endcase

endmodule

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
    output wire BFISA,
    output wire [7:0] symbol
);

`include "keyboard_keys.sv" 

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
    .BFISA(BFISA)
);

reg currentIsa;
reg nextIsa;


assign BFISA = currentIsa;

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

