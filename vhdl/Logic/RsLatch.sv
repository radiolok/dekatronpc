module RsLatch(
    input wire S,
    input wire R,
    output reg Q
);

always_latch begin
    if (S)
    Q = 1'b1;
    if (R)
    Q = 1'b0;
end
endmodule

module Rs3Latch_en(
    input wire Sa,
    input wire Sb,
    input wire R,
    input wire en,
    output reg Qa,
    output reg Qb,
    output wire Q_n
);

assign Q_n = ~(Qa | Qb);
/* verilator lint_off NOLATCH */
always_latch begin
    if (en & Sa) begin
        Qa = 1'b1;
    end
    if (R|Sb) begin
        Qa = 1'b0;
    end
end
always_latch begin
    if (en & Sb) begin
        Qb = 1'b1;
    end
    if (R|Sa) begin
        Qb = 1'b0;
    end
end
/* verilator lint_on NOLATCH */
endmodule
