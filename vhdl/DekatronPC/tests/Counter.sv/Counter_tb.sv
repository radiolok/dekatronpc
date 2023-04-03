module Counter_tb #(
    parameter DEKATRON_NUM = 6
);

parameter TEST_NUM=50;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #1 hsClk = ~hsClk;
end
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);

reg Request = 1'b0;
reg Dec;
reg Set;
reg [DEKATRON_NUM*4-1:0] In;

wire Ready;

wire [DEKATRON_NUM*4-1:0] Out;

DekatronCounter  #(.D_NUM(DEKATRON_NUM)
)counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Request),
                .Dec(Dec),
                .Set(Set),
                .In(In),
                .Ready(Ready),
                .Out(Out)
            );

initial begin $dumpfile("Counter_tb.vcd"); 
$dumpvars(0, Counter_tb); end


initial begin
    Dec <= 0;
    Set <= 1;
    In <= 0;
    #3
    Set <= 0;
    Rst_n <= 0;
    #1  Rst_n <= 1;
    $display("Increment test");
    for (integer i=0; i < TEST_NUM; i++) begin
    repeat(1) @(posedge Clk) 
	$display("test %d: Out: %x", i, Out);
    end
    $display("Decrement test");
    Dec <= 1;
    for (integer i=0; i < TEST_NUM; i++) begin
    repeat(1) @(posedge Clk) 
	$display("test %d: Out: %x", i, Out);
    end
    if (Out == 0) $display($time, "Counter Up/Down Test Sussess!");
    $display($time, "<< Simulation Complete >>");
    $finish;
end

always @(negedge Clk, Rst_n) begin
    if (~Rst_n)
        Request <= 0;
    else
        Request <= Ready;
end

endmodule
