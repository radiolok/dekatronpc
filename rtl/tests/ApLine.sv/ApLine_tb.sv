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
// CLRD, STORE, CLRML, CLRA с выгрузкой, переход 255 <-> 0 и число
// обращений к памяти (ленивое чтение, выгрузка при MemLock).
// Монитор обращений к памяти проверяет, что mem_valid не выставляется
// без mem_ready: стробы ApLine поднимаются только при готовности всех
// исполнителей, и рукопожатие происходит в том же такте.
//
// Кодом операции служит сама инструкция {insn_mode, insn} (REQ-APV2-008).
// Тест пользуется прежними именами операций, do_op переводит их в опкод:
// направление d выбирает парный код ('-' 0x13, '<' 0x15), для CLRD —
// Debug 0x0A вместо BF 0x1A, для TEST — ']' вместо '['.
//----------------------------------------------------------------------
module ApLine_tb (
);
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #50 hsClk = ~hsClk;
end

parameter TEST_NUM = 20000;

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

reg             valid    = 1'b0;
reg  [4:0]      op       = 5'h10;   // BF NOP
reg  [11:0]     rx_data  = 12'd0;

wire            ready;
wire            data_zero;
wire            data_zero_valid;
wire            ap_zero;
wire            mem_lock;
wire [11:0]     tx_data_bcd;
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
    OP_LOAD      = 4'd7,
    OP_STORE     = 4'd8,
    OP_CLRML     = 4'd9,
    OP_TEST      = 4'd10;

ApLine apLine (
    .rst_n          (Rst_n),
    .clk            (Clk),
    .hs_clk         (hsClk),
    .soft_rst       (1'b0),
    .hard_rst       (1'b0),
    .valid          (valid),
    .ready          (ready),
    .op             (op),
    .data_zero      (data_zero),
    .data_zero_valid(data_zero_valid),
    .ap_zero        (ap_zero),
    .mem_lock       (mem_lock),
    .rx_data_bcd    (rx_data),
    .tx_data_bcd    (tx_data_bcd),
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
    .EN_OVERLAY    (1'b0)
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
        OP_AP_STEP:   insn_of = d ? 5'h15 : 5'h14;   // <  >
        OP_AP_ZERO:   insn_of = 5'h0B;               // CLRA
        OP_DATA_STEP: insn_of = d ? 5'h13 : 5'h12;   // -  +
        OP_DATA_ZERO: insn_of = d ? 5'h0A : 5'h1A;   // CLRD, [-]
        OP_CIN:       insn_of = 5'h19;
        OP_COUT:      insn_of = 5'h18;
        OP_LOAD:      insn_of = 5'h1C;
        OP_STORE:     insn_of = 5'h1D;
        OP_CLRML:     insn_of = 5'h1B;
        OP_TEST:      insn_of = d ? 5'h17 : 5'h16;   // ]  [
        default:      insn_of = 5'h10;               // NOP
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
    op      <= 5'h10;
    rx_data <= 12'd0;

    #2000 Rst_n <= 1'b1;
    while (!ready) @(posedge Clk);

    $display("AP increment test");
    for (int i = 1; i <= 20; i++) begin
        do_op(OP_AP_STEP, 1'b0, 12'd0);
        if (MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", MemAddr, ap_bcd(i));
        end
    end

    $display("AP decrement test");
    for (int i = 19; i >= 0; i--) begin
        do_op(OP_AP_STEP, 1'b1, 12'd0);
        if (MemAddr !== ap_bcd(i)) begin
            errors++;
            $display("FAIL: AP=%h expected=%h", MemAddr, ap_bcd(i));
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

    $display("AP move flushes cell, LOAD reads it back");
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP 0->1, cell0 := 6
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP 1->0, cell1 := 0
    do_op(OP_LOAD,     1'b0, 12'd0);        // Data := cell0
    if (tx_data_bcd[11:0] !== data_bcd(6)) begin
        errors++;
        $display("FAIL: LOAD -> %0d, expected 6", tx_data_bcd);
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
    do_op(OP_LOAD,     1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== data_bcd(65)) begin
        errors++;
        $display("FAIL: CIN flush/LOAD -> %0d, expected 65", tx_data_bcd);
    end

    $display("DATA_ZERO test");
    do_op(OP_DATA_ZERO, 1'b0, 12'd0);
    if (tx_data_bcd[11:0] !== 12'd0) begin
        errors++;
        $display("FAIL: DATA_ZERO -> %0d, expected 0", tx_data_bcd);
    end

    // Ячейка 0 = 0 в счётчике, MemLock. Дальше счёт обращений идёт с нуля.
    $display("STORE test");
    do_op(OP_CIN,   1'b0, data_bcd(123));
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_STORE, 1'b0, 12'd0);
    check_mem("STORE", 0, 1);
    if (!mem_lock) begin
        errors++;
        $display("FAIL: STORE released mem_lock");
    end
    // MemLock — единственный флаг: шаг адреса выгружает счётчик ещё раз
    // и снимает MemLock (REQ-ML-005), обратный шаг памяти не трогает
    do_op(OP_AP_STEP, 1'b0, 12'd0);
    if (mem_lock) begin
        errors++;
        $display("FAIL: mem_lock after AP step after STORE");
    end
    do_op(OP_AP_STEP, 1'b1, 12'd0);
    check_mem("AP step after STORE", 0, 2);
    do_op(OP_LOAD, 1'b0, 12'd0);           // регистр памяти ушёл с адреса
    check_mem("LOAD after AP step", 1, 2);
    check_data("STORE/LOAD", 123);

    $display("Lazy read: AP steps do not touch memory");
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    for (int i = 0; i < 10; i++) do_op(OP_AP_STEP, 1'b0, 12'd0);
    for (int i = 0; i < 10; i++) do_op(OP_AP_STEP, 1'b1, 12'd0);
    check_mem("20 AP steps", 0, 0);

    $display("CLRML test");
    do_op(OP_LOAD,      1'b0, 12'd0);      // 123, lock не меняется
    do_op(OP_DATA_STEP, 1'b0, 12'd0);      // 124, MemLock
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_CLRML, 1'b0, 12'd0);
    check_mem("CLRML", 0, 1);
    if (mem_lock) begin
        errors++;
        $display("FAIL: mem_lock after CLRML");
    end
    do_op(OP_TEST, 1'b1, 12'd0);           // ']'; регистр памяти уже на месте
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("TEST/COUT after CLRML", 0, 1);
    check_data("COUT after CLRML", 124);
    if (data_zero || !data_zero_valid) begin
        errors++;
        $display("FAIL: data_zero=%b valid=%b after CLRML", data_zero, data_zero_valid);
    end
    do_op(OP_CLRML, 1'b0, 12'd0);          // без MemLock: без записи
    check_mem("second CLRML", 0, 1);

    $display("CLRA flushes a locked cell");
    do_op(OP_AP_STEP,   1'b0, 12'd0);      // AP=1
    do_op(OP_DATA_STEP, 1'b0, 12'd0);      // чтение ячейки 1 (0), +1
    check_data("cell1 +", 1);
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_AP_ZERO, 1'b0, 12'd0);
    check_mem("CLRA", 0, 1);
    if (!ap_zero || MemAddr !== AP_ZERO_BCD) begin
        errors++;
        $display("FAIL: CLRA -> AP=%h", MemAddr);
    end
    do_op(OP_LOAD, 1'b0, 12'd0);
    check_data("cell0 after CLRA", 124);
    do_op(OP_AP_STEP, 1'b0, 12'd0);
    do_op(OP_LOAD,    1'b0, 12'd0);
    check_data("cell1 after CLRA", 1);

    // Вывод всегда со счётчика данных. После шага адреса без MemLock
    // счётчик и регистр памяти относятся к прежней ячейке: COUT обязан
    // прочитать новую и загрузить её в счётчик (OPEN-017, `>.`)
    $display("COUT after an AP step without MemLock");
    do_op(OP_AP_STEP, 1'b1, 12'd0);        // AP=0, счётчик держит 1 (ячейка 1)
    mem_rd_cnt = 0; mem_wr_cnt = 0;
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("COUT after AP step", 1, 0);
    check_data("COUT cell0", 124);
    do_op(OP_AP_STEP, 1'b0, 12'd0);        // AP=1
    do_op(OP_COUT, 1'b0, 12'd0);
    check_mem("COUT after AP step back", 2, 0);
    check_data("COUT cell1", 1);
    do_op(OP_COUT, 1'b0, 12'd0);           // регистр памяти на месте: без чтения
    check_mem("second COUT", 2, 0);
    check_data("second COUT", 1);
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

    // Оба кода обнуления: Debug CLRD 0x0A и BF [-] 0x1A
    do_op(OP_DATA_ZERO, 1'b1, 12'd0);
    check_data("CLRD 0x0A", 0);
    do_op(OP_CIN,       1'b0, data_bcd(7));
    do_op(OP_DATA_ZERO, 1'b0, 12'd0);
    check_data("[-] 0x1A", 0);

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us ApLine Test Success!");
    if (errors) $fatal(1, "ApLine test failed");
    $finish;
end

endmodule
