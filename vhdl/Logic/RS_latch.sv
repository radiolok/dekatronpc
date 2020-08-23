module SR_latch_gate (
    input R, 
    input S, 
    output Q, 
    output Q_n);
    nor (Q, R, Q_n);
    nor (Q_n, S, Q);
endmodule 