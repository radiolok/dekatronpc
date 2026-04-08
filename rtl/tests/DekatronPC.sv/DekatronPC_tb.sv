`timescale 100 ns / 100 ps

module DekatronPC_tb(
);
reg Run;
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

reg [INSN_WIDTH-1:0] InsnMem [0:255];
reg [INSN_WIDTH-1:0] InsnIn;
reg [7:0] InsnInputAddr;
reg [7:0] nextInsnInputAddr;
wire InsnInLoading;
wire InsnInReady;
reg InsnInValid;

assign nextInsnInputAddr = InsnInputAddr + 1'b1;

initial begin
    $readmemh("../firmware.hex", InsnMem);
end

always_ff @(posedge Clk or negedge Rst_n) begin
    if (~Rst_n) begin
        InsnInputAddr <= '0;
        InsnIn <= InsnMem[8'b0];
        InsnInValid <= 1'b0;
    end
    else if (InsnInReady & InsnInValid) begin
        InsnIn <= InsnMem[nextInsnInputAddr];
        InsnInputAddr <= nextInsnInputAddr;
        InsnInValid <= $urandom_range(0, 100) < 10;
    end
    else if (~InsnInValid) begin
        InsnInValid <= $urandom_range(0, 100) < 10;
    end
end

initial begin
    forever begin
        @(posedge Clk);
        if (InsnInReady & InsnInValid & ~InsnInLoading) begin
            $error("Unexpected handshake!");
        end
    end
end

parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
wire [2:0] state;
wire IsHalted;
assign IsHalted = state == 3'b100;

reg RunOnSoftRst;
reg RunOnHardRst;
reg SoftRstOnEOT;

DekatronPC  dekatronPC(
    .SoftRst_n(1'b1),
    .HardRst_n(Rst_n),
    .hsClk(hsClk),
    .Clk(Clk),
    .Run(Run),
    .Halt(1'b0),
    .Step(1'b0),
    .keyPrevIp(1'b0),
    .keyNextIp(1'b0),
    .InsnLoadingStart(1'b0),
    .InsnLoadingStop(1'b0),
    .state(state),
    .InsnIn(InsnIn),
    .InsnInLoading(InsnInLoading),
    .InsnInValid(InsnInValid),
    .InsnInReady(InsnInReady),

    .RunOnHardRst(RunOnHardRst),
    .RunOnSoftRst(RunOnSoftRst),
    .SoftRstOnEOT(SoftRstOnEOT),

    .tx_rdy(1'b1)
);
initial begin 
    $dumpfile("DekatronPC_tb.vcd"); 
    $dumpvars(0,DekatronPC_tb); 
end

initial begin 
RunOnHardRst <= 0;
RunOnSoftRst <= 1;
SoftRstOnEOT <= 1;

Run <= 0;
Rst_n <= 0;

#5 
Rst_n <= 1;
#100
Run <= 1;
#100
Run <= 0;

repeat(1) @(posedge IsHalted)

repeat(1) @(posedge IsHalted)
$finish;

end

parameter TIMEOUT = 1000000;
int clk_cnt;

initial begin
    clk_cnt <= 0;

    forever begin
        @(posedge Clk);
        clk_cnt <= clk_cnt + 1;

        if (clk_cnt >= TIMEOUT) begin
            $error("TIMEOUT");
            $finish;
        end
    end
end

endmodule
