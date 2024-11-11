`timescale 100 ns / 100 ps

module Emulator_tb(
);
reg Rst_n;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #0.5 hsClk = ~hsClk;
end
parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;

Emulator #(.DIVIDE_TO_1US(1)) emulator(
    .KEY({1'b0,Rst_n}),
    .FPGA_CLK_50(hsClk)
);
initial begin 
    $dumpfile("Emulator_tb.vcd"); 
    $dumpvars(0,Emulator_tb); 
end

initial begin 
Rst_n <= 0;

#5 
Rst_n <= 1;

#100000
$finish();
end
endmodule
