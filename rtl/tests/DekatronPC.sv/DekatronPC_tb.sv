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

//----------------------------------------------------------------------
// DekatronPC_tb — интеграционный тест верхнего уровня (v0.7)
//
// Интерфейс DUT обновлён:
//   Rst_n/HardRst_n              -> rst_n + SoftRstKey/HardRstKey
//   RunOnSoftRst/SoftRstOnEOT    -> плюс Echo/Bell-тумблеры
//   tx_rdy(1'b1)                 -> честная линия tx_rdy
//   state[2:0]                   -> state[3:0], is_halted отдельным выходом
//   + rx_data_bcd/rx_vld, Insn, LoopCount, Bell, LoopOverflow,
//     IpAddress1/ApAddress1/RomData1/ApData1/IRET
//----------------------------------------------------------------------
module DekatronPC_tb;

reg Clk;
reg hsClk;
reg rst_n;

reg SoftRstKey;
reg HardRstKey;
reg Halt;
reg Step;
reg Run;
reg InsnLoadingStart;
reg InsnLoadingStop;
reg keyNextIp;
reg keyPrevIp;
reg key_next_app_i;

reg EchoMode;
reg RunOnHardRst;
reg RunOnSoftRst;
reg SoftRstOnEOT;
reg BellOnCIN;
reg BellOnHALT;
reg BellOnError;

reg  [INSN_WIDTH-1:0] InsnIn;
reg  InsnInValid;
wire InsnInReady;
wire InsnInLoading;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   IpAddress;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ApAddress;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount;
wire [INSN_WIDTH-1:0]                       Insn;
wire [3:0]                                  state;
wire IsHalted;
wire Bell;
wire LoopOverflow;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   IpAddress1;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ApAddress1;
wire [INSN_WIDTH-1:0]                       RomData1;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1;
wire [31:0]                                 IRET;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd;
wire tx_vld;
reg  tx_rdy;
reg  [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd;
reg  rx_vld;

initial begin
    hsClk = 1'b0;
    forever #1 hsClk = ~hsClk;
end

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

//----------------------------------------------------------------------
// Загрузчик программы: выдаёт InsnIn по handshake
//----------------------------------------------------------------------
reg [INSN_WIDTH-1:0] InsnMem [0:4095];
reg [11:0] InsnInputAddr;

initial begin
    $readmemh(`PROGRAM_PATH, InsnMem);
end

always_ff @(posedge Clk or negedge rst_n) begin
    if (~rst_n) begin
        InsnInputAddr <= '0;
        InsnIn        <= InsnMem[12'd0];
        InsnInValid   <= 1'b0;
    end
    else if (InsnInReady & InsnInValid) begin
        InsnInputAddr <= InsnInputAddr + 12'd1;
        InsnIn        <= InsnMem[InsnInputAddr + 12'd1];
        InsnInValid   <= 1'b1;
    end
end

//----------------------------------------------------------------------
// Приём терминала
//----------------------------------------------------------------------
`ifdef EXPECTED_OUTPUT
string expected_tx = `EXPECTED_OUTPUT;
`else
string expected_tx = "";
`endif

wire [7:0] tx_data;
byte tx_q [$];

BcdToAscii bcd_to_ascii(
    .Bcd(tx_data_bcd),
    .Ascii(tx_data)
);

task automatic read_tx();
    tx_rdy <= 1'b0;
    forever begin
        repeat (10) @(posedge Clk);
        tx_rdy <= 1'b1;
        @(posedge Clk);
        if (tx_vld & tx_rdy) begin
            $display("TX: %c (%0d)", tx_data, tx_data);
            tx_q.push_back(tx_data);
            tx_rdy <= 1'b0;
        end
    end
endtask

initial begin
    read_tx();
end

//----------------------------------------------------------------------
// DUT
//----------------------------------------------------------------------
DekatronPC #(
    .EN_EMULATOR (1'b0)
) dekatronPC (
    .hsClk           (hsClk),
    .Clk             (Clk),
    .rst_n           (rst_n),

    .SoftRstKey      (SoftRstKey),
    .HardRstKey      (HardRstKey),
    .Halt            (Halt),
    .Step            (Step),
    .Run             (Run),
    .InsnLoadingStart(InsnLoadingStart),
    .InsnLoadingStop (InsnLoadingStop),
    .keyNextIp       (keyNextIp),
    .keyPrevIp       (keyPrevIp),
    .key_next_app_i  (key_next_app_i),

    .EchoMode        (EchoMode),
    .RunOnHardRst    (RunOnHardRst),
    .RunOnSoftRst    (RunOnSoftRst),
    .SoftRstOnEOT    (SoftRstOnEOT),
    .BellOnCIN       (BellOnCIN),
    .BellOnHALT      (BellOnHALT),
    .BellOnError     (BellOnError),

    .tx_data_bcd     (tx_data_bcd),
    .tx_vld          (tx_vld),
    .tx_rdy          (tx_rdy),
    .rx_data_bcd     (rx_data_bcd),
    .rx_vld          (rx_vld),

    .InsnIn          (InsnIn),
    .InsnInValid     (InsnInValid),
    .InsnInReady     (InsnInReady),
    .InsnInLoading   (InsnInLoading),

    .IpAddress       (IpAddress),
    .ApAddress       (ApAddress),
    .LoopCount       (LoopCount),
    .Insn            (Insn),
    .state           (state),
    .IsHalted        (IsHalted),
    .Bell            (Bell),
    .LoopOverflow    (LoopOverflow),

    .IpAddress1      (IpAddress1),
    .ApAddress1      (ApAddress1),
    .RomData1        (RomData1),
    .ApData1         (ApData1),
    .IRET            (IRET)
);

//----------------------------------------------------------------------
// Тактовые операции
//----------------------------------------------------------------------
task automatic wait_relay();
    wait (dekatronPC.rst_busy);
    wait (~dekatronPC.rst_busy);
    repeat (8) @(posedge Clk);
endtask

task automatic soft_rst_key();
    @(posedge Clk);
    SoftRstKey = 1'b1;
    repeat (4) @(posedge Clk);
    SoftRstKey = 1'b0;
    wait_relay();
    wait (IsHalted);
    repeat (4) @(posedge Clk);
endtask

task automatic hard_rst_key();
    @(posedge Clk);
    HardRstKey = 1'b1;
    repeat (4) @(posedge Clk);
    HardRstKey = 1'b0;
    wait_relay();
    wait (IsHalted);
    repeat (4) @(posedge Clk);
endtask

task automatic key_next();
    keyNextIp = 1'b1;
    repeat (6) @(posedge Clk);
    keyNextIp = 1'b0;
    repeat (6) @(posedge Clk);
endtask

task automatic key_prev();
    keyPrevIp = 1'b1;
    repeat (6) @(posedge Clk);
    keyPrevIp = 1'b0;
    repeat (6) @(posedge Clk);
endtask

task automatic press_run();
    Run = 1'b1;
    repeat (4) @(posedge Clk);
    Run = 1'b0;
    repeat (4) @(posedge Clk);
endtask

//----------------------------------------------------------------------
// Проверки
//----------------------------------------------------------------------
int errors = 0;

task automatic check_ip_moving();
    $display("check_ip_moving");
    soft_rst_key();

    if (!IsHalted) begin
        errors++;
        $display("FAIL: expected IsHalted after soft reset");
    end
    if (IpAddress !== 20'h00000) begin
        errors++;
        $display("FAIL: IP after soft reset = %h, expected 0", IpAddress);
    end

    for (int i = 0; i < 10; i++) key_next();
    if (IpAddress !== 20'h00010) begin
        errors++;
        $display("FAIL: IP after 10 inc = %h, expected 10", IpAddress);
    end

    for (int i = 0; i < 10; i++) key_prev();
    if (IpAddress !== 20'h00000) begin
        errors++;
        $display("FAIL: IP after 10 dec = %h, expected 0", IpAddress);
    end
endtask

task automatic check_bootloader();
    $display("check_bootloader");
    RunOnHardRst = 1'b0;
    RunOnSoftRst = 1'b1;
    SoftRstOnEOT = 1'b1;
    hard_rst_key();
    press_run();

    if (IsHalted) begin
        errors++;
        $display("FAIL: expected running after Run");
    end

    @(posedge InsnInLoading);
    @(negedge InsnInLoading);
    @(posedge IsHalted);
    repeat (20) @(posedge Clk);

    if (tx_q.size() !== expected_tx.len()) begin
        errors++;
        $display("FAIL: TX size expected %0d, actual %0d",
                 expected_tx.len(), tx_q.size());
    end
    else begin
        for (int i = 0; i < expected_tx.len(); i++) begin
            byte cur = tx_q.pop_front();
            if (cur !== expected_tx[i]) begin
                errors++;
                $display("FAIL: TX[%0d] expected %0d, actual %0d",
                         i, expected_tx[i], cur);
            end
        end
    end
endtask

//----------------------------------------------------------------------
// Основной сценарий
//----------------------------------------------------------------------
initial begin
    rst_n            <= 1'b0;
    SoftRstKey       <= 1'b0;
    HardRstKey       <= 1'b0;
    Halt             <= 1'b0;
    Step             <= 1'b0;
    Run              <= 1'b0;
    InsnLoadingStart <= 1'b0;
    InsnLoadingStop  <= 1'b0;
    keyNextIp        <= 1'b0;
    keyPrevIp        <= 1'b0;
    key_next_app_i   <= 1'b0;
    EchoMode         <= 1'b0;
    RunOnHardRst     <= 1'b0;
    RunOnSoftRst     <= 1'b0;
    SoftRstOnEOT     <= 1'b0;
    BellOnCIN        <= 1'b0;
    BellOnHALT       <= 1'b0;
    BellOnError      <= 1'b0;
    rx_data_bcd      <= 12'd0;
    rx_vld           <= 1'b0;
    tx_rdy           <= 1'b0;
    InsnInValid      <= 1'b0;
    InsnIn           <= 4'h0;

    repeat (20) @(posedge hsClk);
    rst_n <= 1'b1;
    wait_relay();
    wait (IsHalted);

    // После включения реле времени даёт аппаратный сброс: IP = 99900
    if (IpAddress !== 20'h99900) begin
        errors++;
        $display("FAIL: IP after power-up = %h, expected 99900", IpAddress);
    end

`ifdef TRY_PROGRAM
    check_bootloader();
`endif

    check_ip_moving();

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us DekatronPC Test Success!");
    if (errors) $fatal(1, "DekatronPC test failed");
    $finish;
end

//----------------------------------------------------------------------
// Сторож
//----------------------------------------------------------------------
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

`ifndef NO_VCD
initial begin
    $dumpfile("DekatronPC_tb.vcd");
    $dumpvars(0, DekatronPC_tb);
end
`endif

endmodule
