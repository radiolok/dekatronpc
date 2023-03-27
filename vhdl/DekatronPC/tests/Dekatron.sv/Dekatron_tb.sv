module dekatron_tb(
);
parameter WIDTH=10;
reg hsClk;
reg Clk;
reg PulseRight;
reg PulseLeft;
reg [WIDTH-1:0] In;
wire[WIDTH-1:0] Out;
reg Rst_n;

wire Ready = |Out & ~PulseLeft & ~PulseRight;

Clock_divider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);

dekatron  dek(
    .hsClk(hsClk),
    .PulseRight(PulseRight),
    .PulseLeft(PulseLeft),
    .In(In),
    .Out(Out)
);

initial begin $dumpfile("dekatron_tb.vcd"); 
$dumpvars(0,dekatron_tb); end

initial begin
    hsClk = 1'b0;
    forever #1 hsClk = ~hsClk;
end

initial begin
    PulseRight <= 0;
    PulseLeft <= 0;
    In <= 10'b0;
    Rst_n <= 0;
    #1  Rst_n <= 1;
end

reg [20:0]test_num=10;

reg [9:0] data = 10'b1;

always @(posedge Clk, Rst_n) begin
    if (Rst_n) begin
        test_num <=test_num-1;
        if (test_num==0) $finish;
        data <= {data[8:0], data[9]};
        In <=  data;
        #3 
        In <= 10'b0;
        end
end

endmodule
