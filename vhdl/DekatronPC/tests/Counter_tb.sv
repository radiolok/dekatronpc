module counter_tb #(
    parameter DEKATRON_NUM = 6,
    parameter COUNT_DELAY = 3//delay in clockticks between Req and Rdy
);

reg Clk;
reg Rst_n;

reg Request;
reg Dec;
reg Set;
reg [DEKATRON_NUM*3-1:0] In;

wire Ready;

wire [DEKATRON_NUM*3-1:0] Out;

Counter  #(.DEKATRON_NUM(DEKATRON_NUM),
            .COUNT_DELAY(COUNT_DELAY))
            counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(Request),
                .Dec(Dec),
                .Set(Set),
                .In(In),
                .Ready(Ready),
                .Out(Out)
            );



initial begin
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial begin
    Dec <= 0;
    Set <= 0;
    In <= 0;
    #5  Rst_n <= 1;
    #200
	$display($time, "<< Simulation Complete >>");
	$stop;
end

always @(negedge Clk, Rst_n) begin
    if (~Rst_n)
        Request <= 0;
    else
        Request <= Ready;
end

endmodule