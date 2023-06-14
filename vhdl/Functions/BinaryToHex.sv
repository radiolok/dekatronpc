function [3:0] BinaryToHex(
    input [15:0] Binary
);
  case(Binary)
    16'b0000000000000001: BinaryToHex = 4'h0;
    16'b0000000000000010: BinaryToHex = 4'h1;
    16'b0000000000000100: BinaryToHex = 4'h2;
    16'b0000000000001000: BinaryToHex = 4'h3;
    16'b0000000000010000: BinaryToHex = 4'h4;
    16'b0000000000100000: BinaryToHex = 4'h5;
    16'b0000000001000000: BinaryToHex = 4'h6;
    16'b0000000010000000: BinaryToHex = 4'h7;
    16'b0000000100000000: BinaryToHex = 4'h8;
    16'b0000001000000000: BinaryToHex = 4'h9;
    16'b0000010000000000: BinaryToHex = 4'hA;
    16'b0000100000000000: BinaryToHex = 4'hB;
    16'b0001000000000000: BinaryToHex = 4'hC;
    16'b0010000000000000: BinaryToHex = 4'hD;
    16'b0100000000000000: BinaryToHex = 4'hE;
    16'b1000000000000000: BinaryToHex = 4'hF;
    default: BinaryToHex = 4'h0;
  endcase
endfunction
