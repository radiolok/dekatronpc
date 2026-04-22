`timescale 100 ns / 100 ps

`ifdef ADDINCLUDE
`include `ADDINCLUDE
`endif

`ifndef PROGRAM_PATH
`define PROGRAM_PATH "../firmware.hex"
`endif

`ifndef TIMEOUT
`define TIMEOUT 200000
`endif

module DekatronPC_tb;

reg SoftRst_n;
reg HardRst_n;
reg Clk;
reg hsClk;

reg Run;
reg Halt;
reg Step;
reg RunOnSoftRst;
reg RunOnHardRst;
reg SoftRstOnEOT;

localparam IP_WIDTH = IP_DEKATRON_NUM*DEKATRON_WIDTH;
localparam AP_WIDTH = AP_DEKATRON_NUM*DEKATRON_WIDTH;
wire [IP_WIDTH-1:0] IpAddress;
wire [AP_WIDTH-1:0] ApAddress;

reg keyNextIp;
reg keyPrevIp;

wire Rst_n;
assign Rst_n = SoftRst_n & HardRst_n;

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

reg [INSN_WIDTH-1:0] InsnMem [0:2048];
reg [INSN_WIDTH-1:0] InsnIn;
reg [7:0] InsnInputAddr;
reg [7:0] nextInsnInputAddr;
wire InsnInLoading;
wire InsnInReady;
reg InsnInValid;

assign nextInsnInputAddr = InsnInputAddr + 1'b1;

initial begin
    $readmemh(`PROGRAM_PATH, InsnMem);
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

string expected_tx = `EXPECTED_OUTPUT;
reg tx_rdy;
wire tx_vld;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd;
wire [7:0] tx_data;
byte tx_q [$];

BcdToAscii bcd_to_ascii(
    .Bcd(tx_data_bcd),
    .Ascii(tx_data)
);

task read_tx();
    tx_rdy <= 1'b0;
    wait(Rst_n);
    
    forever begin
        repeat($urandom_range(0, 10)) @(posedge Clk);

        tx_rdy <= 1'b1;

        do begin
            @(posedge Clk);
        end
        while(~(tx_vld & tx_rdy));

        tx_rdy <= 1'b0;

        $display("%c", tx_data);
        tx_q.push_back(tx_data);
    end
endtask

parameter TEST_NUM=20000;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
wire [2:0] state;
wire IsHalted;
assign IsHalted = state == 3'b100;

DekatronPC  dekatronPC(
    .SoftRst_n(SoftRst_n),
    .HardRst_n(HardRst_n),
    .hsClk(hsClk),
    .Clk(Clk),
    .Run(Run),
    .Halt(Halt),
    .Step(Step),
    .keyPrevIp(keyPrevIp),
    .keyNextIp(keyNextIp),
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

    .IpAddress(IpAddress),
    .ApAddress(ApAddress),

    .tx_data_bcd(tx_data_bcd),
    .tx_vld(tx_vld),
    .tx_rdy(1'b1)
);

task soft_rst();
    SoftRst_n <= 1'b0;
    #100
    SoftRst_n <= 1'b1;
endtask

task hard_rst();
    HardRst_n <= 1'b0;
    #5
    HardRst_n <= 1'b1;
endtask

task run();
    Run <= 1;
  #100
    Run <= 0;
endtask

task inc_ip();
    keyNextIp <= 1'b1;
    #100;
    keyNextIp <= 1'b0;
    #50;
endtask

task dec_ip();
    keyPrevIp <= 1'b1;
    #100;
    keyPrevIp <= 1'b0;
endtask

task step();
    Step <= 1'b1;
    #100;
    Step <= 1'b0;
endtask

task check_ip_moving();
    RunOnSoftRst <= 0;
    soft_rst();
    #200;

    if (~IsHalted) begin
        $error("Expected IsHalted after Soft Rst!");
    end

    if (IpAddress != IP_WIDTH'(8'h00)) begin
        $error("IP after soft rst mismatch! Expected 0, Actual %h", IpAddress);
    end

    for (int i = 0; i < 10; i++) begin
        inc_ip();
        #200;
    end

    if (IpAddress != IP_WIDTH'(8'h10)) begin
        $error("IP increment mismatch! Expected %h, Actual %h", IP_WIDTH'(8'h10), IpAddress);
    end

    for (int i = 0; i < 10; i++) begin
        dec_ip();
        #200;
    end

    if (IpAddress != IP_WIDTH'(8'h00)) begin
        $error("IP decrement mismatch! Expected 0, Actual %h", IpAddress);
    end
endtask

task check_steps();
    RunOnSoftRst <= 0;
    soft_rst();
    #200;

    if (~IsHalted) begin
        $error("Expected IsHalted after Soft Rst!");
    end

    if (IpAddress != IP_WIDTH'(8'h00)) begin
        $error("IP after soft rst mismatch! Expected 0, Actual %h", IpAddress);
    end

    for (int i = 0; i < 10; i++) begin
        step();
        #500;
        wait(IsHalted);
    end

    if (IpAddress != IP_WIDTH'(8'h10)) begin
        $error("Step count mismatch! Expected %h, Actual %h", IP_WIDTH'(8'h10), IpAddress);
    end
endtask

task check_bootloader();
    RunOnHardRst <= 0;
    RunOnSoftRst <= 1;
    SoftRstOnEOT <= 1;
    hard_rst();
    #100

    if (~IsHalted) begin
        $error("Expected IsHalted after Hard Rst!");
    end

    run();

    if (IsHalted) begin
        $error("Expected running after Run!");
    end

    @(posedge InsnInLoading);
    @(negedge InsnInLoading);

    @(posedge IsHalted);
    @(posedge IsHalted);

    check_tx();
endtask

task check_tx();
    byte cur_char;

    if (tx_q.size() !== expected_tx.len()) begin
        $error("TX mismatch! Expected %d, Actual %d", expected_tx.len(), tx_q.size());
    end
    else begin
        for (int i = 0; i < expected_tx.len(); i = i + 1) begin
            cur_char = tx_q.pop_front();
            if (cur_char !== expected_tx[i]) begin
                $error("TX %d-th mismatch! Expected %d, Actual %d", i, expected_tx[i], cur_char);
            end
        end
    end
endtask

initial begin
    read_tx();
end

initial begin 
    RunOnHardRst <= 0;
    RunOnSoftRst <= 1;
    SoftRstOnEOT <= 1;
    HardRst_n <= 1;
    SoftRst_n <= 1;
    Run <= 0;
    Step <= 0;
    Halt <= 0;
    keyNextIp <= 0;
    keyPrevIp <= 0;

    check_bootloader();

`ifndef DISABLE_CHECK_IP_MOVIND
    check_ip_moving();
`endif

`ifndef DISABLE_CHECK_STEPS
    check_steps();
`endif

    $finish;
end

`ifndef NO_VCD
initial begin 
    $dumpfile("DekatronPC_tb.vcd"); 
    $dumpvars(0,DekatronPC_tb); 
end
`endif

int clk_cnt;

initial begin
    clk_cnt <= 0;

    forever begin
        @(posedge Clk);
        clk_cnt <= clk_cnt + 1;

        if (clk_cnt >= `TIMEOUT) begin
            $error("TIMEOUT");
            $finish;
        end
    end
end

endmodule
