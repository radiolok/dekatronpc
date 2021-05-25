module UpCounter #(
parameter TOP = 4'b1001
)(
    input wire Clk,
    input wire Rst_n,
    input wire Enable,
    output reg [4:0] Count
);

always @(posedge Clk, negedge Rst_n) begin
    Count <=  (!Rst_n) ? 0 :
            (Count == TOP) ? 0:
            (Enable)? Count + 1 : Count;
end

endmodule

module Keyboard(
    input [7:0] kbCol,
    input [6:0] kbRow,
    input write,
    input read,
    input clear
);

endmodule

module Ms6205(
    output [7:0] address,
    output [7:0] data,
    input write_addr,
    input write_data,
    input ready
);

endmodule

module DekatronPC(
    output reg  [17:0] ipCounter,
    output reg [8:0] loopCounter,
    output reg [14:0] apCounter,
    output reg [8:0] dataCounter
);

endmodule

module Impulse(
    input Clock,
    input Enable,
    input Rst_n,
    output wire Impulse
);

reg D_state;

assign Impulse = Enable & ~D_state;

always @(posedge Clock, negedge Rst_n) begin
    if (~Rst_n)
        D_state <= 1'b0;
    else
        D_state <= Enable;
end

endmodule