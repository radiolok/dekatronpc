module Counter_tb #(
    parameter DEKATRON_NUM = 3
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

reg [7:0] REF;

DekatronCounter  #(.D_NUM(DEKATRON_NUM),
                    .TOP_LIMIT_MODE(1'b1),
                    .TOP_VALUE({4'd2, 4'd5, 4'd5})
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
    REF <= 24'd0;
    #3
    Set <= 0;
    Rst_n <= 0;
    #1  Rst_n <= 1;
    $display("Increment test");
    for (integer i=0; i < TEST_NUM; i++) begin
        REF <= REF + 1;
        repeat(1) @(posedge Clk)
        repeat(1) @(posedge Clk)
        $display("test %d: Out: %x. REF: %d", i, Out, REF);
        if (REF % 10 != Out[3:0]) begin
            $fatal(1, "Counter0 Up Failure REF: %d Out: %d", REF % 10, Out[3:0]);
        end
        if ((REF/10) % 10 != Out[7:4]) begin
            $fatal(1, "Counter1 Up Failure REF: %d Out: %d", (REF/10) % 10, Out[7:4]);
        end
        if ((REF/100) % 10 != Out[11:8]) begin
            $fatal(1, "Counter2 Up Failure REF: %d Out: %d", (REF/100) % 10, Out[11:8]);
        end        
    end
    $display("Decrement test");
    for (integer i=0; i < TEST_NUM; i++) begin
        REF <= REF - 1;
        Dec <= 1;
        repeat(1) @(posedge Clk)
        Dec <= 1'b0;
        repeat(1) @(posedge Clk)
        $display("test %d: Out: %x. REF: %d", i, Out, REF);
        if (REF % 10 != Out[3:0]) begin
            $fatal(1, "Counter0 Down Failure REF: %d Out: %d", REF % 10, Out[3:0]);
        end
        if ((REF/10) % 10 != Out[7:4]) begin
            $fatal(1, "Counter1 Down Failure REF: %d Out: %d", (REF/10) % 10, Out[7:4]);
        end
        if ((REF/100) % 10 != Out[11:8]) begin
            $fatal(1, "Counter2 Down Failure REF: %d Out: %d", (REF/100) % 10, Out[11:8]);
        end
    end
    if (Out == 0) 
        $display($time, "Counter Up/Down Test Sussess!");
    else 
        $fatal(1, "Must be zero!");
    
    for (integer i=0; i < 256; i++) begin
        REF <= REF + 1;
        repeat(1) @(posedge Clk)
        repeat(1) @(posedge Clk)
        $display("test %d: Out: %x. REF: %d", i, Out, REF);
    end
    if (Out == 0) 
        $display($time, "Counter RollUp Test Sussess!");
    else 
        $fatal(1, "Must be zero!");
    $display($time, "<< Simulation Complete >>");
    $finish;
end

always @(posedge Clk, Rst_n) begin
    if (~Rst_n)
        Request <= 0;
    else
        if (Ready)
            Request <= 1'b1;
        if (Request)
            Request <= 1'b0;
end

endmodule
