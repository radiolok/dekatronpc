module mux_2w 
#(
    parameter WIDTH=1
)(
    input [WIDTH-1:0] d0, d1,
    input sel,
    output [WIDTH-1:0] y
);

assign y = sel ? d1 : d0;

endmodule


module mux_4w 
#(
    parameter WIDTH=1
)(
    input [WIDTH-1:0] d0, d1, d2, d3,
    input [1:0] sel,
    output wire [WIDTH-1:0] y
);

assign y = (sel == 2'b00) ? d0:
        (sel == 2'b01) ? d1:
        (sel == 2'b10) ? d2: d3;

endmodule


module mux_3b_8w (
    input [2:0] d0, d1, d2, d3, d4, d5, d6, d7,
    input [3:0] sel,
    output [2:0] y
);

assign y = (sel == 3'b000) ? d0:
        (sel == 3'b001) ? d1:
        (sel == 3'b010) ? d2:
        (sel == 3'b011) ? d3:
        (sel == 3'b100) ? d4:
        (sel == 3'b101) ? d5:
        (sel == 3'b110) ? d6: d7;


endmodule

module mux_3b_9w (
    input [2:0] d0, d1, d2, d3, d4, d5, d6, d7, d8,
    input [3:0] sel,
    output [2:0] y
);

assign y = (sel == 4'b0000) ? d0:
        (sel == 4'b0001) ? d1:
        (sel == 4'b0010) ? d2:
        (sel == 4'b0011) ? d3:
        (sel == 4'b0100) ? d4:
        (sel == 4'b0101) ? d5:
        (sel == 4'b0110) ? d6:
        (sel == 4'b0111) ? d7:
        (sel == 4'b1000) ? d8: 4'b0000;

endmodule

module mux_8b_5w (
    input [7:0] d0, d1, d2, d3, d4, 
    input [2:0] sel,
    output [7:0] y
);

assign y = (sel == 3'b000) ? d0:
        (sel == 3'b001) ? d1:
        (sel == 3'b010) ? d2:
        (sel == 3'b011) ? d3:
        (sel == 3'b100) ? d4: 8'b0000000;

endmodule