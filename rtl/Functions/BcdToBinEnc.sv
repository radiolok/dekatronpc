module BcdToBinEnc #(
    parameter DIGITS = 6,
    parameter MAX_VAL = 10**DIGITS-1,
    parameter OUT_WIDTH = $clog2(MAX_VAL)
)(
    input wire [4*DIGITS-1:0] bcd,
    output wire [OUT_WIDTH-1:0] bin
);
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off UNOPTFLAT */
wire [DIGITS*OUT_WIDTH-1:0] conv;
generate
    genvar i;
    for(i = 0; i < DIGITS; i=i+1) begin: MUL
        if (i == 0) begin: MUL_1
            assign conv[OUT_WIDTH*(i+1)-1:OUT_WIDTH*i] = bcd[4*(i+1)-1:4*i];
        end
        else begin: MUL_10
            assign conv[OUT_WIDTH*(i+1)-1:OUT_WIDTH*i] = bcd[4*(i+1)-1:4*i] * (10**i) + conv[OUT_WIDTH*(i)-1:OUT_WIDTH*(i-1)];
        end     
    end
endgenerate
    assign bin = conv[OUT_WIDTH*(DIGITS)-1:OUT_WIDTH*(DIGITS-1)];
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on UNOPTFLAT */
endmodule
