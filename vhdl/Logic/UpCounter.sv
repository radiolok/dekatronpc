module UpCounter #(
    parameter TOP = 4'b1001,
    parameter WIDTH=4
)(
    input wire Tick,
    input wire Rst_n,
    output reg [WIDTH-1:0] Count
);
/* verilator lint_off WIDTHEXPAND */
always @(posedge Tick, negedge Rst_n) begin
    Count <=  (!Rst_n) ? {WIDTH{1'b0}} :
            (Count == TOP) ? {WIDTH{1'b0}}:
            Count + 1;
end
/* verilator lint_on WIDTHEXPAND */
endmodule
