module Register #(
    parameter WIDTH = 8
)(
    input wire Rst_n,
    input wire En,
    input wire Cs,
    input wire [WIDTH-1:0] In,
    output reg [WIDTH-1:0] Out
);

always @(posedge En, negedge Rst_n) begin
    if (~Rst_n) Out <= {WIDTH{1'b0}};
    else if (Cs) Out <= In;
end
endmodule

