`timescale 100 ns / 100 ps

module DekatronPC_tb(
);
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #0.5 hsClk = ~hsClk;
end
parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);


DekatronPC  dekatronPC(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk)
);
initial begin 
    $dumpfile("DekatronPC_tb.vcd"); 
    $dumpvars(0,DekatronPC_tb); 
end

initial begin 
Rst_n <= 0;

#5 
Rst_n <= 1;

end
endmodule
