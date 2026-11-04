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
`ifndef DEKATRON_DELAY_MODEL
reg hsClk;
`endif
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
// Шины значений DekatronPC — активным нулём (TC-O3, Приложение B);
// тестбенч, как и эмулятор, работает с прямым кодом
wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   IpAddress_n;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   ApAddress_n;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount_n;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd_n;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1_n;
assign IpAddress   = ~IpAddress_n;
assign ApAddress   = ~ApAddress_n;
assign LoopCount   = ~LoopCount_n;
assign tx_data_bcd = ~tx_data_bcd_n;
assign ApData1     = ~ApData1_n;
wire tx_vld;
reg  tx_rdy;
reg  [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd;
reg  rx_vld;
wire rx_rdy;

`ifdef DEKATRON_DELAY_MODEL
// Период Clk в нс (synth_sim.sh -c): поиск частоты, на которой работает
// нетлист с задержками ламп (doc/vtube_sdf_timing.md)
`ifndef CLK_NS
`define CLK_NS CLK_PERIOD_NS
`endif
// Модель на задержках: hsClk нет вовсе, у DekatronPC нет и порта
// [TRS v0.25]. Первый фронт Clk через 100 нс после снятия rst_n.
initial begin
    Clk = 1'b0;
    wait (rst_n === 1'b1);
    #1;
    forever begin
        Clk = 1'b1; #(`CLK_NS / 200.0);   // timescale 100 ns
        Clk = 1'b0; #(`CLK_NS / 200.0);
    end
end
`else
initial begin
    hsClk = 1'b0;
    // hsClk = 10 x Clk (HSCLK_NS = CLK_PERIOD_NS / 10, TRS v0.24);
    // timescale 100 ns
    forever #(HSCLK_NS / 200.0) hsClk = ~hsClk;
end

ClockDivider #(
    .DIVISOR(HSCLK_DIV)
) clock_divider_ms(
    .Rst_n(rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);
`endif

//----------------------------------------------------------------------
// Загрузчик программы: выдаёт InsnIn по handshake
//----------------------------------------------------------------------
reg [INSN_WIDTH-1:0] InsnMem [0:4095];
reg [11:0] InsnInputAddr;

// ISA16: режима нет, первым загрузчик выдаёт NOP (адрес 0), затем
// программу; она кончается на LD (EOT)
initial begin
    InsnMem[0] = 4'h0;
    $readmemh(`PROGRAM_PATH, InsnMem, 1);
end

// Внешний источник: на фронте Clk его данные гарантированно читаемы,
// меняет он их только на спаде (TRS Приложение B). Ламповые триггеры
// ловят фронт через инвертор такта (≈ 250 нс), и смена данных на самом
// фронте давала гонку по удержанию в synth_sim.sh -t (TC-N2)
reg insn_in_take;   // рукопожатие на последнем фронте

always @(posedge Clk or negedge rst_n)
    if (~rst_n) insn_in_take <= 1'b0;
    else        insn_in_take <= InsnInReady & InsnInValid;

always_ff @(negedge Clk or negedge rst_n) begin
    if (~rst_n) begin
        InsnInputAddr <= '0;
        InsnIn        <= InsnMem[12'd0];
        InsnInValid   <= 1'b0;
    end
    else if (insn_in_take) begin
        InsnInputAddr <= InsnInputAddr + 12'd1;
        InsnIn        <= InsnMem[InsnInputAddr + 12'd1];
        InsnInValid   <= 1'b1;
    end
    else if (~InsnInValid) begin
        InsnInValid <= 1'b1;
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

// tx_rdy поднимается раз в 11 тактов и держится до рукопожатия. Как
// у внешнего источника, tx_rdy меняется только на спаде Clk (TRS
// Приложение B). Линии смотрим на спаде Clk: после фронта автомат уже
// снял tx_vld, и чтение сразу после фронта теряло символы.
task automatic read_tx();
    tx_rdy <= 1'b0;
    forever begin
        repeat (10) @(posedge Clk);
        @(negedge Clk);
        tx_rdy <= 1'b1;
        while (!tx_vld) @(negedge Clk);   // рукопожатие — на следующем фронте
        $display("TX: %c (%0d)", tx_data, tx_data);
        tx_q.push_back(tx_data);
        @(posedge Clk);                 // рукопожатие на этом фронте
        @(negedge Clk);
        tx_rdy <= 1'b0;
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
`ifndef DEKATRON_DELAY_MODEL
    .hsClk           (hsClk),
`endif
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

    .tx_data_bcd     (tx_data_bcd_n),
    .tx_vld          (tx_vld),
    .tx_rdy          (tx_rdy),
    .rx_data_bcd     (~rx_data_bcd),
    .rx_vld          (rx_vld),
    .rx_rdy          (rx_rdy),

    .InsnIn          (InsnIn),
    .InsnInValid     (InsnInValid),
    .InsnInReady     (InsnInReady),
    .InsnInLoading   (InsnInLoading),

    .IpAddress       (IpAddress_n),
    .ApAddress       (ApAddress_n),
    .LoopCount       (LoopCount_n),
    .Insn            (Insn),
    .state           (state),
    .IsHalted        (IsHalted),
    .Bell            (Bell),
    .LoopOverflow    (LoopOverflow),

    .IpAddress1      (IpAddress1),
    .ApAddress1      (ApAddress1),
    .RomData1        (RomData1),
    .ApData1         (ApData1_n),
    .IRET            (IRET)
);

//----------------------------------------------------------------------
// Тактовые операции
//----------------------------------------------------------------------
// Кнопки пульта меняются на спаде Clk, как и прочие входы внешних
// источников (TRS v0.46, Приложение B, §22 п. 19). Прежде они
// выставлялись по фронту, и блокирующее присваивание сразу после
// @(posedge Clk) было гонкой с автоматом на том же фронте. Кнопки
// сброса идут на асинхронное реле времени; по спаду их снятие реле
// приходилось за 1 мкс до фронта, и без синхронизатора rst_busy в
// MachineCtrl synth_sim.sh -t падал (doc/external_inputs_falling_edge.md
// §5). Этот сценарий и проверяет синхронизатор.

// IsHalted — дешифратор состояния автомата. В нетлисте биты состояния
// меняются в разных дельта-циклах, и при переходе в S_EXEC дешифратор
// на нулевое время проходит через S_HALT. wait()/@(posedge) ловят этот
// всплеск, поэтому линию смотрим на спаде Clk, как и tx_vld.
task automatic wait_halted();
    do @(negedge Clk); while (!IsHalted);
endtask

task automatic wait_relay();
    wait (dekatronPC.rst_busy);
    wait (~dekatronPC.rst_busy);
    repeat (8) @(posedge Clk);
endtask

task automatic soft_rst_key();
    @(negedge Clk);
    SoftRstKey <= 1'b1;
    repeat (4) @(negedge Clk);
    SoftRstKey <= 1'b0;
    wait_relay();
    wait_halted();
    repeat (4) @(posedge Clk);
endtask

task automatic hard_rst_key();
    @(negedge Clk);
    HardRstKey <= 1'b1;
    repeat (4) @(negedge Clk);
    HardRstKey <= 1'b0;
    wait_relay();
    wait_halted();
    repeat (4) @(posedge Clk);
endtask

task automatic key_next();
    @(negedge Clk);
    keyNextIp <= 1'b1;
    repeat (6) @(negedge Clk);
    keyNextIp <= 1'b0;
    repeat (6) @(posedge Clk);
endtask

task automatic key_prev();
    @(negedge Clk);
    keyPrevIp <= 1'b1;
    repeat (6) @(negedge Clk);
    keyPrevIp <= 1'b0;
    repeat (6) @(posedge Clk);
endtask

task automatic press_run();
    @(negedge Clk);
    Run <= 1'b1;
    repeat (4) @(negedge Clk);
    Run <= 1'b0;
    repeat (4) @(posedge Clk);
endtask

//----------------------------------------------------------------------
// Проверки
//----------------------------------------------------------------------
int errors = 0;

task automatic check_ip_moving();
    $display("check_ip_moving");
    RunOnSoftRst <= 1'b0;                // иначе сброс снова запустит программу
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
    RunOnHardRst <= 1'b0;
    RunOnSoftRst <= 1'b1;
    SoftRstOnEOT <= 1'b1;
    hard_rst_key();
    press_run();

    if (IsHalted) begin
        errors++;
        $display("FAIL: expected running after Run");
    end

    @(posedge InsnInLoading);
    $display("  bootloader: loading started"); $fflush;
    @(negedge InsnInLoading);
    $display("  bootloader: loading finished"); $fflush;
    $display("  state=%0d IP=%h Insn=%h", state, IpAddress, Insn); $fflush;
    wait_halted();
    $display("  bootloader: halted"); $fflush;
    $display("  state=%0d IP=%h Insn=%h", state, IpAddress, Insn); $fflush;
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

`ifdef DEKATRON_DELAY_MODEL
    // 10 мкс: на нетлисте с задержками ламп логика после X включения
    // устанавливается ~2,1 мкс, и при прежних 1,95 мкс первый фронт Clk
    // защёлкивал X в автомат MachineCtrl (doc/vtube_sta.md §6). В машине
    // rst_n держит реле времени, логика к его снятию давно установилась.
    // Clk запускается от снятия rst_n, число тактов не меняется.
    #99.5;
`else
    repeat (20) @(posedge hsClk);
`endif
    rst_n <= 1'b1;
    wait_relay();
    wait_halted();

    // После включения реле времени даёт аппаратный сброс: IP = 99990
    if (IpAddress !== 20'h99990) begin
        errors++;
        $display("FAIL: IP after power-up = %h, expected 99990", IpAddress);
    end

`ifdef TRY_PROGRAM
    check_bootloader();
`endif

    check_ip_moving();

    if (errors)
        $display($time/10, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/10, "us DekatronPC Test Success!");
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
            $fatal(1, "TIMEOUT");
        end
    end
end

`ifdef POWER_VCD
// Power run (synth_sim.sh -p, doc/vtube_power.md): only the DUT, into the
// FIFO that vtube_power_vcd reads, so the VCD of pi.bfk never lands on disk
initial begin
    $dumpfile(`POWER_VCD);
    $dumpvars(0, DekatronPC_tb.dekatronPC);
end
`elsif NO_VCD
`else
initial begin
    $dumpfile("DekatronPC_tb.vcd");
    $dumpvars(0, DekatronPC_tb);
end
`endif

endmodule
