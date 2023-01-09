module counter_tb #(
    parameter D_NUM = 6,
    parameter COUNT_DELAY = 3//delay in clockticks between Req and Rdy
);

reg Clk;
reg Rst_n;

reg Request;
reg Dec;
reg Set;
reg [D_NUM*4-1:0] In;

wire Ready;

wire [D_NUM*4-1:0] Out;

Counter  #(.D_NUM(D_NUM),
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
    $dumpfile("Counter.vcd");
    $dumpvars(0, counter_tb);
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial begin
    Dec <= 0;
    Set <= 0;
    In <= 0;
    Rst_n <= 0;
    #1  Rst_n <= 1;
    #(COUNT_DELAY*50*2)
    Dec <= 1;
    #(COUNT_DELAY*50*2)
    if (Out != 0) $display($time, "<< Count up/down mistmatch! >>");
    In <= 39;
    Set <= 1;
    #3
    Set <= 0;
    In <= 0;
    #(COUNT_DELAY*39*2)
    if (Out != 0) $display($time, "<< Count up/down mistmatch! >>");
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