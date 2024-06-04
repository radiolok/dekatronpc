/* verilator lint_off DECLFILENAME */
module BCDCounterX1(
    input wire Clk,
    input wire Rst_n,
    input wire ci,
    output reg co,
    output reg [3 : 0] count
);

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        count <= 4'd0;
        co <= 1'b0;
    end else begin
        if (ci) begin
            if (count == 4'd9) begin
                count <= 4'd0;
                co <= 1'b1;
            end
            else begin
                count <= count + 4'd1;
                co <= 1'b0;
            end
        end
    end
end
endmodule

module BCDCounter #(
    parameter DIGITS = 2
)(
    input wire Clk,
    input wire Rst_n,
    output wire[DIGITS*4-1:0] count
);

    genvar i;
    wire [DIGITS-1:0] ci;
    wire [DIGITS-1:0] co;
    generate
        for (i = 0; i < DIGITS; i= i + 1) begin: digits
            if (i == 0) begin
                assign ci[i] = 1'b1;
            end
            else begin
                assign ci[i] = co[i-1];
            end
            if (i == DIGITS-1)begin
                /* verilator lint_off UNUSEDSIGNAL */
                wire co_o = co[i];
                /* verilator lint_on UNUSEDSIGNAL */
            end
            BCDCounterX1 U_digitCounter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .ci(ci[i]),
                .co(co[i]),
                .count(count[4*(i+1)-1:4*i])
                );
        end
    endgenerate
endmodule
