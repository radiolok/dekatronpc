`timescale 100 ns / 100 ps

module DekatronPC_tb(
);
reg Rst_n;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #0.5 hsClk = ~hsClk;
end
parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;

DekatronPC  dekatronPC(
    .Rst_n(Rst_n),
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
