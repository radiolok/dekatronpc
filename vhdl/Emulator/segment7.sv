//Verilog module.
module segment7(
     input wire [3:0] hex,
     output reg [6:0] seg
    );

//always block for converting bcd digit into 7 segment format
    always @(hex)
    begin
        case (hex) //case statement
            0 : seg = 7'b0111111;
            1 : seg = 7'b0000110;
            2 : seg = 7'b1011011;
            3 : seg = 7'b1001111;
            4 : seg = 7'b1100110;
            5 : seg = 7'b1101101;
            6 : seg = 7'b1111101;
            7 : seg = 7'b0000111;
            8 : seg = 7'b1111111;
            9 : seg = 7'b1101111;
            4'hA: seg = 7'b1110111;
            4'hB: seg = 7'b1111100;
            4'hC: seg = 7'b0111001;
            4'hD: seg = 7'b1011110;
            4'hE: seg = 7'b1111001;
            4'hF: seg = 7'b1110001;
            //switch off 7 segment character when the bcd digit is not a decimal number.
            default : seg = 7'b0000000; 
        endcase
    end
    
endmodule
