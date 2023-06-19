function [3:0] In12CathodeToPin(
    input  [3:0] in
);

case (in)
    4'd0: In12CathodeToPin = 4'd1;
    4'd1: In12CathodeToPin = 4'd0;
    4'd2: In12CathodeToPin = 4'd2;
    4'd3: In12CathodeToPin = 4'd3;
    4'd4: In12CathodeToPin = 4'd6;
    4'd5: In12CathodeToPin = 4'd8;
    4'd6: In12CathodeToPin = 4'd9;
    4'd7: In12CathodeToPin = 4'd7;
    4'd8: In12CathodeToPin = 4'd5;
    4'd9: In12CathodeToPin = 4'd4;
    default: In12CathodeToPin = 4'hA;
endcase
endfunction
