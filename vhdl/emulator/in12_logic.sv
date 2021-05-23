module UpCounter #(
parameter TOP = 4'b1001
)(
    input wire Clk,
    input wire Rst_n,
    output reg [4:0] Count
);

always @(posedge Clk, negedge Rst_n) begin
    Count <=  (!Rst_n) ? 0 :
            (Count == TOP) ? 0:
                Count + 1;
end

endmodule

module Keyboard(
    input [7:0] kbCol,
    input [6:0] kbRow,
    output write,
    output clear
);

endmodule

module Ms6205(
    output [7:0] address,
    output [7:0] data,
    output write_addr,
    output write_data,
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