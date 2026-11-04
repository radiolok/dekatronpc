`timescale 1ns/1ps

//----------------------------------------------------------------------
// ApLine_tb — тест блока работы с данными (Valid/Ready, v0.7)
//
// Интерфейс DUT обновлён:
//   DataZero/ApZero/ApRequest/DataRequest/Dec/Ready ->
//   data_zero/ap_zero/valid/ready/op/dec/data_zero_valid/mem_lock
//   RAM (Address/In/Out/WE/CS) -> Ram (valid/ready/wr/addr/wr_data/
//                                    rd_data/rd_valid/err/ovl_*)
//
// Проверяется AP-счётчик, чтение ячейки (TEST) и шаг данных (+), CIN,
// [-], MemLock (копирование ячейки), CLRA с выгрузкой, переход 255 <-> 0 и число
// обращений к памяти (ленивое чтение, выгрузка при MemLock).
// Монитор обращений к памяти проверяет, что mem_valid не выставляется
// без mem_ready: стробы ApLine поднимаются только при готовности всех
// исполнителей, и рукопожатие происходит в том же такте.
//
// Кодом операции служит сам опкод ISA16 (REQ-APV2-008, doc/isa16.md).
// Тест пользуется именами операций, do_op переводит их в опкод:
// направление d выбирает парный код ('-' 0x3, '<' 0x5), для TEST —
// ']' вместо '['.
//----------------------------------------------------------------------
module ApLine_tb (
);
reg Rst_n;
reg Clk;
`ifndef DEKATRON_DELAY_MODEL
reg hsClk;
`endif
parameter TEST_NUM = 20000;

`ifdef DEKATRON_DELAY_MODEL
// Модель на задержках: hsClk нет вовсе [TRS v0.25]; Clk напрямую с
// периодом CLK_NS, первый фронт через 50 нс после снятия Rst_n
`ifndef CLK_NS
`define CLK_NS CLK_PERIOD_NS
`endif
initial begin
    Clk = 1'b0;
    wait (Rst_n === 1'b1);
    #50;
    forever begin
        Clk = 1'b1; #(`CLK_NS / 2.0);
        Clk = 1'b0; #(`CLK_NS / 2.0);
    end
end
`else
initial begin
    hsClk = 1'b1;
    forever #(HSCLK_NS / 2.0) hsClk = ~hsClk;   // Clk / HSCLK_DIV
end


ClockDivider #(
    .DIVISOR(HSCLK_DIV)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);
`endif

reg             valid    = 1'b0;
// Линия аппаратного сброса: держится при включении, как реле времени
// (RST_ON_POWERUP). Триггеры клея rst_n не получают
// (REQ-REF-011, TC-O5)
reg             HardRst  = 1'b0;
reg  [3:0]      op       = 4'h0;    // NOP
reg  [11:0]     rx_data  = 12'd0;

wire            ready;
wire            data_zero;
wire            data_zero_valid;
wire            ap_zero;
wire            mem_lock;
wire [11:0]     tx_data_bcd;
// Терминальные шины ApLine — активным нулём (TC-O3); тестбенч работает
// с прямым кодом
wire [11:0]     tx_data_bcd_n;
assign tx_data_bcd = ~tx_data_bcd_n;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] MemAddr;
wire [9:0]      MemWrData;
wire [9:0]      MemRdData;
wire            MemValid;
wire            MemReady;
wire            MemWr;
wire            MemRdValid;
wire            MemErr;

localparam [3:0]
    OP_NOP       = 4'd0,
    OP_AP_STEP   = 4'd1,
    OP_AP_ZERO   = 4'd2,
    OP_DATA_STEP = 4'd3,
    OP_DATA_ZERO = 4'd4,
    OP_CIN       = 4'd5,
    OP_COUT      = 4'd6,
    OP_MEMLOCK     = 4'd8,
    OP_TEST      = 4'd10;

ApLine apLine (
    .rst_n          (Rst_n),
    .clk            (Clk),
`ifndef DEKATRON_DELAY_MODEL
    .hs_clk         (hsClk),
`endif
    .soft_rst       (1'b0),
    .hard_rst       (HardRst),
    .valid          (valid),
    .ready          (ready),
    .op             (op),
    .data_zero      (data_zero),
    .data_zero_valid(data_zero_valid),
    .ap_zero        (ap_zero),
    .mem_lock       (mem_lock),
    .rx_data_bcd    (~rx_data),
    .tx_data_bcd    (tx_data_bcd_n),
    .mem_addr       (MemAddr),
    .mem_wr_data    (MemWrData),
    .mem_rd_data    (MemRdData),
    .mem_valid      (MemValid),
    .mem_ready      (MemReady),
    .mem_wr         (MemWr),
    .mem_rd_valid   (MemRdValid),
    .mem_err        (MemErr)
);

Ram #(
    .D_NUM         (AP_DEKATRON_NUM),
    .DATA_WIDTH    (10),
    .READ_CYCLES   (1),
    .WRITE_CYCLES  (1),
    .INIT_ZERO     (1'b1),
    .EN_DBG_PORT   (1'b0),
    .EN_OVERLAY    (1'b0),
    .ADDR_ACTIVE_LOW (1'b1),   // как в DekatronPC (TC-O3)
    .DATA_ACTIVE_LOW (1'b1)
) ram (
    .clk      (Clk),
    .rst_n    (Rst_n),
    .valid    (MemValid),
    .ready    (MemReady),
    .wr       (MemWr),
    .addr     (MemAddr),
    .wr_data  (MemWrData),
    .rd_data  (MemRdData),
    .rd_valid (MemRdValid),
    .err      (MemErr),
    .ovl_hit  (1'b0),
    .ovl_data (10'h0),
    .dbg_addr (20'h0),
    .dbg_data ()
);

localparam [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] AP_ZERO_BCD =
    {AP_DEKATRON_NUM{4'd0}};

function automatic [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ap_bcd(input int unsigned v);
    reg [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] r;
    int unsigned t;
    t = v;
    r = '0;
    for (int i = 0; i < AP_DEKATRON_NUM; i++) begin
        r[4*i +: 4] = t % 10;
        t = t / 10;
    end
    return r;
endfunction

function automatic [11:0] data_bcd(input int unsigned v);
    data_bcd = {4'((v/100)%10), 4'((v/10)%10), 4'(v%10)};
endfunction

initial begin $dumpfile("ApLine_tb.vcd"); $dumpvars(0, ApLine_tb); end

reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > 2000000)
      $fatal(1, "Timeout");
  end
end

//----------------------------------------------------------------------
// Одна операция по Valid/Ready
//----------------------------------------------------------------------
function automatic [4:0] insn_of(input [3:0] o, input bit d);
    case (o)
        OP_AP_STEP:   insn_of = d ? 4'h5 : 4'h4;   // <  >
        OP_AP_ZERO:   insn_of = 4'hC;              // CLRA
        OP_DATA_STEP: insn_of = d ? 4'h3 : 4'h2;   // -  +
        OP_DATA_ZERO: insn_of = 4'hA;              // [-]
        OP_CIN:       insn_of = 4'h9;
        OP_COUT:      insn_of = 4'h8;
        OP_MEMLOCK:     insn_of = 4'hD;
        OP_TEST:      insn_of = d ? 4'h7 : 4'h6;   // ]  [
        default:      insn_of = 4'h0;              // NOP
    endcase
endfunction

task automatic do_op(input [3:0] o, input bit d, input [11:0] rx);
    @(negedge Clk);
    while (!ready) @(negedge Clk);
    valid   = 1'b1;
    op      = insn_of(o, d);
    rx_data = rx;
    @(posedge Clk);          // accept
    @(negedge Clk);
    valid = 1'b0;
    while (!ready) @(negedge Clk);
endtask

int errors = 0;

//----------------------------------------------------------------------
// Монитор обращений к памяти
//----------------------------------------------------------------------
int mem_rd_cnt = 0;
int mem_wr_cnt = 0;

always @(posedge Clk) begin
    if (Rst_n && MemValid) begin
        if (!MemReady) begin
            errors++;
            $display("FAIL: mem_valid without mem_ready");
        end
        else if (MemWr) mem_wr_cnt++;
        else            mem_rd_cnt++;
    end
end

task automatic check_data(input string what, input int unsigned v);
    if (tx_data_bcd[11:0] !== data_bcd(v)) begin
        errors++;
        $display("FAIL: %s -> %h, expected %0d", what, tx_data_bcd, v);
    end
endtask

task automatic check_mem(input string what, input int rd, input int wr);
    if (mem_rd_cnt !== rd || mem_wr_cnt !== wr) begin
        errors++;
        $display("FAIL: %s: mem reads=%0d writes=%0d, expected %0d/%0d",
                 what, mem_rd_cnt, mem_wr_cnt, rd, wr);
    end
endtask

initial begin
    Rst_n   <= 1'b0;
    valid   <= 1'b0;
    op      <= 4'h0;
    rx_data <= 12'd0;

    HardRst <= 1'b1;
    #2000 Rst_n <= 1'b1;
    repeat (12) @(posedge Clk);
    HardRst <= 1'b0;
    @(posedge Clk);
    while (!ready) @(posedge Clk);

    $display("AP increment test");
    for (int i = 1; i <= 20; i++) begin
        do_op(OP_AP_STEP, 1'b0, 12'd0);
        if (~MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", ~MemAddr, ap_bcd(i));
        end
    end

    $display("AP decrement test");
    for (int i = 19; i >= 0; i--) begin
        do_op(OP_AP_STEP, 1'b1, 12'd0);
        if (~MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", ~MemAddr, ap_bcd(i));
        end
    end
    if (!ap_zero) begin
        errors++;
        $display("FAIL: ap_zero not set at AP=0");
    end

    $display("Memory TEST at AP=0");
    do_op(OP_TEST, 1'b0, 12'd0);
    if (!data_zero_valid) begin
        errors++;
        $display("FAIL: data_zero_valid not set after TEST");
    end
    if (!data_zero) begin
        errors++;
        $display("FAIL: data_zero not set for zero cell");
    end

    $display("Memory COUT at AP=0");
    do_op(OP_COUT, 1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== 12'd0) begin
        errors++;
        $display("FAIL: tx_data_bcd after COUT = %0d, expected 0", tx_data_bcd);
    end

    $display("Data step test (lazy read)");
    for (int i = 1; i <= 10; i++) begin
        do_op(OP_DATA_STEP, 1'b0, 12'd0);
        if (tx_data_bcd[11:0] !== data_bcd(i)) begin
            errors++;
            $display("FAIL: data + -> %0d, expected %0d", tx_data_bcd, i);
        end
    end
    for (int i = 9; i >= 6; i--) begin
        do_op(OP_DATA_STEP, 1'b1, 12'd0);
        if (tx_data_bcd[11:0] !== data_bcd(i)) begin
            errors++;
            $display("FAIL: data - -> %0d, expected %0d", tx_data_bcd, i);
        end
    end

    $display("AP move flushes cell, COUT reads it back");
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP 0->1, cell0 := 6
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP 1->0
    do_op(OP_COUT,     1'b0, 12'd0);        // Data := cell0
    if (tx_data_bcd[11:0] !== data_bcd(6)) begin
        errors++;
        $display("FAIL: COUT -> %0d, expected 6", tx_data_bcd);
    end

    // rx_data держится do_op до ready: входного регистра в ApLine нет
    $display("CIN test (rx_data_bcd held until ready)");
    do_op(OP_CIN, 1'b0, data_bcd(65));
    if (tx_data_bcd[11:0] !== data_bcd(65) || !mem_lock) begin
        errors++;
        $display("FAIL: CIN -> %0d lock=%b, expected 65 lock=1", tx_data_bcd, mem_lock);
    end
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP 0->1, cell0 := 65
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP 1->0
    do_op(OP_COUT,     1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== data_bcd(65)) begin
        errors++;
        $display("FAIL: CIN flush/COUT -> %0d, expected 65", tx_data_bcd);
    end

    $display("DATA_ZERO test");
    do_op(OP_DATA_ZERO, 1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== 12'd0) begin
        errors++;
        $display("FAIL: DATA_ZERO -> %0d, expected 0", tx_data_bcd);
    end

    // Ячейка 0 = 0 в счётчике, MemLock. Дальше счёт обращений идёт с нуля.
    // MemLock только ставит MemLock: счётчик забирает текущую ячейку со
    // своим прежним значением, следующий шаг адреса выгружает его в неё.
    // '>' MemLock '<' копирует ячейку 0 в ячейку 1
    $display("MemLock: copy a cell through the data counter");
    do_op(OP_CIN, 1'b0, data_bcd(123));    // cell0 := 123 в счётчике, MemLock
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // cell0 := 123, AP=1
    if (mem_lock) begin
        errors++;
        $display("FAIL: mem_lock after AP step");
    end
    do_op(OP_MEMLOCK, 1'b0, 12'd0);
    check_mem("MEMLOCK", 0, 1);
    if (!mem_lock || data_zero || !data_zero_valid) begin
        errors++;
        $display("FAIL: MemLock: lock=%b data_zero=%b valid=%b", mem_lock, data_zero, data_zero_valid);
    end
    check_data("MemLock keeps the counter", 123);
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // cell1 := 123, AP=0
    check_mem("AP step after MemLock", 0, 2);
    do_op(OP_COUT, 1'b0, 12'd0);           // регистр памяти ушёл с адреса
    check_data("cell0", 123);
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP=1
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("copy read back", 2, 2);
    check_data("copy in cell1", 123);

    $display("MemLock with MemLock set changes nothing");
    do_op(OP_DATA_STEP, 1'b0, 12'd0);      // 124, значение уже в регистре памяти
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_MEMLOCK, 1'b0, 12'd0);
    check_mem("MemLock with lock", 0, 0);
    check_data("MemLock with lock", 124);
    if (!mem_lock) begin
        errors++;
        $display("FAIL: mem_lock lost after MemLock");
    end
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // cell1 := 124, AP=0
    check_mem("flush after MemLock", 0, 1);

    $display("Lazy read: AP steps do not touch memory");
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    for (int i = 0; i < 10; i++) do_op(OP_AP_STEP, 1'b0, 12'd0);
    for (int i = 0; i < 10; i++) do_op(OP_AP_STEP, 1'b1, 12'd0);
    check_mem("20 AP steps", 0, 0);

    $display("CLRA flushes a locked cell");
    do_op(OP_AP_STEP,   1'b0, 12'd0);      // AP=1
    do_op(OP_DATA_STEP, 1'b0, 12'd0);      // чтение ячейки 1 (124), +1
    check_data("cell1 +", 125);
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_AP_ZERO, 1'b0, 12'd0);
    check_mem("CLRA", 0, 1);
    if (!ap_zero || ~MemAddr !== AP_ZERO_BCD) begin
        errors++;
        $display("FAIL: CLRA -> AP=%h", ~MemAddr);
    end
    do_op(OP_COUT, 1'b0, 12'd0);
    check_data("cell0 after CLRA", 123);
    do_op(OP_AP_STEP, 1'b0, 12'd0);
    do_op(OP_COUT,    1'b0, 12'd0);
    check_data("cell1 after CLRA", 125);

    // Вывод всегда со счётчика данных. После шага адреса без MemLock
    // счётчик и регистр памяти относятся к прежней ячейке: COUT обязан
    // прочитать новую и загрузить её в счётчик (OPEN-017, `>.`)
    $display("COUT after an AP step without MemLock");
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP=0, счётчик держит 125 (ячейка 1)
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("COUT after AP step", 1, 0);
    check_data("COUT cell0", 123);
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP=1
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("COUT after AP step back", 2, 0);
    check_data("COUT cell1", 125);
    do_op(OP_COUT, 1'b0, 12'd0);           // регистр памяти на месте: без чтения
    check_mem("second COUT", 2, 0);
    check_data("second COUT", 125);
    if (mem_lock) begin
        errors++;
        $display("FAIL: COUT set mem_lock");
    end

    $display("Data wrap 255 <-> 0");
    do_op(OP_CIN,       1'b0, data_bcd(255));
    do_op(OP_DATA_STEP, 1'b0, 12'd0);
    check_data("255 +", 0);
    if (!data_zero) begin
        errors++;
        $display("FAIL: data_zero after 255 +");
    end
    do_op(OP_DATA_STEP, 1'b1, 12'd0);
    check_data("0 -", 255);

    do_op(OP_CIN,       1'b0, data_bcd(7));
    do_op(OP_DATA_ZERO, 1'b0, 12'd0);
    check_data("[-] 0xA", 0);

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us ApLine Test Success!");
    if (errors) $fatal(1, "ApLine test failed");
    $finish;
end

endmodule
