`timescale 1ns/1ps

//----------------------------------------------------------------------
// IpLine_tb — тест блока выборки инструкций (Valid/Ready)
//
// Тестовая память программ лежит в этом же файле и загружает
// firmware.hex (генерируется из looptest.bfk скриптом emul).
// Память повторяет дисциплину Ram: ready = ~busy, данные чтения
// появляются только к возврату ready (до этого — X) и держатся до
// следующего обращения, запись сквозная.
//
// Части теста:
//   1. looptest: +++++++++[-+-+-]H, промотка назад
//   2. загрузка программы по insn_in (вложенные скобки [ ] и { }, EOT = LD
//      0xB, insn_eot) и её
//      выполнение со случайным loop_val_zero; каждая выборка
//      сравнивается с эталонной моделью (адрес и опкод), счётчик
//      вложенности после каждой выборки обязан быть нулём
//   3. переполнение счётчика вложенности, снятие программным сбросом
//   4. программный сброс: первая выборка без шага
//   5. останов: шаг IP, ручные шаги вперёд/назад, выборка без шага
//   6. аппаратный сброс: IP = 99990 (ISA16, doc/isa16.md)
//
// Собственного регистра опкода у IpLine нет: insn — выход памяти. Монитор
// проверяет, что insn не меняется, пока память не занята (REQ-IPV2-008).
//----------------------------------------------------------------------

module IpLine_tb_mem #(
    parameter AW  = 20,
    parameter LAT = 2      // тактов занятости на обращение
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid,
    output wire        ready,
    input  wire        wr,
    input  wire [AW-1:0] addr,
    input  wire [3:0]  wr_data,
    output reg  [3:0]  rd_data,
    output wire        rd_valid,
    output wire        err
);

    reg [3:0] mem [0:99999];

    function automatic int bcd2bin(input [AW-1:0] b);
        int r;
        r = 0;
        for (int i = 4; i >= 0; i--)
            r = r*10 + b[4*i +: 4];
        return r;
    endfunction

    localparam int unsigned IDX_W = 20;
    wire [31:0]      addr_bin = bcd2bin(addr);
    wire [IDX_W-1:0] idx      = addr_bin[IDX_W-1:0];

    initial begin
        for (int i = 0; i < 100000; i++) mem[i] = 4'h0;
        // looptest.bfk = 18 инструкций
        $readmemh("../firmware.hex", mem, 0, 16);
    end

    reg       busy;
    reg [3:0] pend;
    int       cnt;

    assign ready    = ~busy;
    assign rd_valid = ~busy;
    assign err      = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            rd_data <= 4'h0;
        end
        else if (!busy) begin
            if (valid) begin
                busy    <= 1'b1;
                cnt     <= LAT;
                rd_data <= 4'hx;
                if (wr) begin
                    mem[idx] <= wr_data;
                    pend     <= wr_data;      // сквозная запись
                end
                else begin
                    pend <= mem[idx];
                end
            end
        end
        else if (cnt <= 1) begin
            busy    <= 1'b0;
            rd_data <= pend;
        end
        else begin
            cnt <= cnt - 1;
        end
    end

endmodule


module IpLine_tb (
);

reg Rst_n;
reg HardRst;      // hard_rst физическая линия
reg SoftRst;
reg Clk;
`ifndef DEKATRON_DELAY_MODEL
reg hsClk;
`endif

parameter TEST_NUM = 2000;
parameter RAND_NUM = 400;     // выборок в части 2

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
    hsClk = 1'b0;
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

reg        ip_valid = 1'b0;
wire       ip_ready;

wire       loop_val_zero;
wire [3:0] Insn;
wire       InsnEot;

reg        HaltRq    = 1'b0;
reg        IpAhead   = 1'b0;
reg        KeyPrev   = 1'b0;
reg        KeyNext   = 1'b0;
reg        Loading   = 1'b0;
reg [3:0]  InsnIn    = 4'h0;
reg        InsnInValid = 1'b0;
wire       InsnInReady;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   Address;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount;
// IpLine выдаёт IP, счётчик циклов и адрес памяти активным нулём (TC-O3);
// тестбенч сравнивает прямые значения, модель памяти берёт прямой адрес
wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   Address_n;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount_n;
wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   MemAddr_n;
assign Address   = ~Address_n;
assign LoopCount = ~LoopCount_n;
assign MemAddr   = ~MemAddr_n;
wire       LoopOverflow;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] MemAddr;
wire [INSN_WIDTH-1:0]                     MemWrData;
wire [INSN_WIDTH-1:0]                     MemRdData;
wire       MemValid;
wire       MemReady;
wire       MemWr;
wire       MemRdValid;
wire       MemErr;

reg [11:0] Data;
reg        rand_mode = 1'b0;
reg        lvz_r     = 1'b0;
assign loop_val_zero = rand_mode ? lvz_r : (Data == 12'd0);

IpLine #(
    .HARD_RST_D_CNT (IP_DEKATRON_NUM - 1),
    .LOOP_READ      (1'b1)
) ipLine (
    .rst_n        (Rst_n),
    .clk          (Clk),
`ifndef DEKATRON_DELAY_MODEL
    .hs_clk       (hsClk),
`endif
    .soft_rst     (SoftRst),
    .hard_rst     (HardRst),
    .valid        (ip_valid),
    .ready        (ip_ready),
    .loop_val_zero(loop_val_zero),
    .insn         (Insn),
    .insn_eot     (InsnEot),
    .halt_rq      (HaltRq),
    .ip_ahead     (IpAhead),
    .key_prev_ip  (KeyPrev),
    .key_next_ip  (KeyNext),
    .insn_loading (Loading),
    .insn_in      (InsnIn),
    .insn_in_valid(InsnInValid),
    .insn_in_ready(InsnInReady),
    .ip_addr      (Address_n),
    .loop_count   (LoopCount_n),
    .loop_overflow(LoopOverflow),
    .mem_addr     (MemAddr_n),
    .mem_wr_data  (MemWrData),
    .mem_rd_data  (MemRdData),
    .mem_valid    (MemValid),
    .mem_ready    (MemReady),
    .mem_wr       (MemWr),
    .mem_rd_valid (MemRdValid),
    .mem_err      (MemErr)
);

IpLine_tb_mem mem (
    .clk      (Clk),
    .rst_n    (Rst_n),
    .valid    (MemValid),
    .ready    (MemReady),
    .wr       (MemWr),
    .addr     (MemAddr),
    .wr_data  (MemWrData),
    .rd_data  (MemRdData),
    .rd_valid (MemRdValid),
    .err      (MemErr)
);

localparam [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] BOOTLOADER_ADDR =
    {4'd9, 4'd9, 4'd9, 4'd9, 4'd0};   // 99990 в BCD

initial begin $dumpfile("IpLine_tb.vcd"); $dumpvars(0, IpLine_tb); end

function automatic int bcd2bin(input [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] b);
    int r;
    r = 0;
    for (int i = IP_DEKATRON_NUM-1; i >= 0; i--)
        r = r*10 + b[4*i +: 4];
    return r;
endfunction

int errors = 0;

// Опкод выбран после сброса: только тогда insn на ready обязан быть
// определён (признака insn_valid у IpLine нет, TC-O9)
reg fetched = 1'b0;
always @(posedge Clk)
    if (SoftRst | HardRst)      fetched <= 1'b0;
    else if (ip_valid & ip_ready) fetched <= 1'b1;

//----------------------------------------------------------------------
// Мониторы
//----------------------------------------------------------------------
always @(posedge Clk) begin
    if (Rst_n && MemValid && !MemReady) begin
        errors++;
        $display("FAIL: mem_valid without mem_ready");
    end
`ifndef NETLIST_SIM
    // Internal strobes: on the netlist the counters are flattened into IpLine
    // and these nets are merged away (synt_dpc.tcl, doc/tube_count_1000.md §4)
    if (Rst_n && ipLine.ip_valid && ipLine.loop_valid) begin
        errors++;
        $display("FAIL: ip_valid and loop_valid together");
    end
`endif
    if (Rst_n && ip_ready && fetched && ^Insn === 1'bx) begin
        errors++;
        $display("FAIL: insn is X at ready");
    end
end

// Опкод держит выходной регистр памяти: без обращения он не меняется,
// как бы ни двигался IP
reg [3:0] insn_prev;
reg       mem_idle_prev = 1'b0;
bit       poked = 0;              // тест сам подложил опкод в регистр памяти
always @(posedge Clk) begin
    if (Rst_n && mem_idle_prev && MemReady && !poked && Insn !== insn_prev) begin
        errors++;
        $display("FAIL: insn changed without a memory access: %h -> %h", insn_prev, Insn);
    end
    insn_prev     <= Insn;
    mem_idle_prev <= MemReady & ~MemValid;
    poked          = 0;
end

//----------------------------------------------------------------------
// Операция по Valid/Ready и ожидание её окончания
//----------------------------------------------------------------------
task automatic do_op();
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    ip_valid = 1'b1;
    @(posedge Clk);              // accept
    @(negedge Clk);
    ip_valid = 1'b0;
    while (!ip_ready) @(negedge Clk);
endtask

//----------------------------------------------------------------------
// Один запрос следующей инструкции. Возвращает retired-опкод.
//----------------------------------------------------------------------
task automatic fetch_insn(output [3:0] code);
    do_op();
    code = Insn;
endtask

//----------------------------------------------------------------------
// Выборка в режиме загрузки: опкод уходит в память по текущему IP
//----------------------------------------------------------------------
task automatic load_insn(input [3:0] code);
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    ip_valid = 1'b1;
    @(posedge Clk);
    @(negedge Clk);
    ip_valid = 1'b0;
    // valid выставляется, не дожидаясь ready, и держится до рукопожатия
    InsnIn      = code;
    InsnInValid = 1'b1;
    while (!InsnInReady) @(negedge Clk);
    @(posedge Clk);              // insn_in_valid & insn_in_ready
    @(negedge Clk);
    InsnInValid = 1'b0;
    InsnIn      = 4'hF;          // загрузчик вправе сменить данные
    while (!ip_ready) @(negedge Clk);
endtask

task automatic pulse_rst(input bit hard);
    @(negedge Clk);
    if (hard) HardRst = 1'b1; else SoftRst = 1'b1;
    repeat (15) @(posedge Clk);    // реле времени: много тактов > RESET_MIN_HS
    @(negedge Clk);
    HardRst = 1'b0;
    SoftRst = 1'b0;
    while (!ip_ready) @(negedge Clk);
endtask

task automatic check_addr(input string what, input int a);
    if (bcd2bin(Address) !== a) begin
        errors++;
        $display("FAIL: %s: IP = %h, expected %0d", what, Address, a);
    end
endtask

task automatic key_step(input bit prev);
    @(negedge Clk);
    if (prev) KeyPrev = 1'b1; else KeyNext = 1'b1;
    repeat (10) @(negedge Clk);    // кнопка держится много тактов
    KeyPrev = 1'b0;
    KeyNext = 1'b0;
    repeat (10) @(negedge Clk);
endtask

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
// Эталонная модель выборки: по прочитанной инструкции и признаку нуля
// в момент запроса — адрес следующей. Скобка, начинающая промотку,
// приводит НА парную скобку. [ ] и { } (x11x) считаются вместе.
//----------------------------------------------------------------------
reg [3:0] prog [0:255];
int       prog_len;

function automatic bit is_open(input [3:0] c);  return c[2:0] == 3'b110; endfunction
function automatic bit is_close(input [3:0] c); return c[2:0] == 3'b111; endfunction

function automatic int ref_next(input int a, input [3:0] c, input bit z);
    int depth;
    if (is_open(c) && z) begin
        depth = 0;
        for (int i = a; i < prog_len; i++) begin
            if (is_open(prog[i]))  depth++;
            if (is_close(prog[i])) depth--;
            if (depth == 0) return i;
        end
        return -1;
    end
    if (is_close(c) && !z) begin
        depth = 0;
        for (int i = a; i >= 0; i--) begin
            if (is_close(prog[i])) depth++;
            if (is_open(prog[i]))  depth--;
            if (depth == 0) return i;
        end
        return -1;
    end
    return a + 1;
endfunction

reg  [3:0] code;
bit  finished = 0;
bit  stop = 0;
int  ref_a, nxt, scans;
bit  z;
integer seed;

// [ + [ - { } ] . [ [ + ] - [ ] ] , ] + - { + }
localparam int PROG_LEN = 23;
localparam [4*PROG_LEN-1:0] PROG = 92'h6263ef78662736779723e2f;

initial begin
    Rst_n   <= 1'b0;
    HardRst <= 1'b0;
    SoftRst <= 1'b0;
    ip_valid<= 1'b0;
    Data    <= 12'd0;

    #2000 Rst_n <= 1'b1;
    // Триггеры клея rst_n не получают: их сбрасывает
    // линия сброса, как реле времени при включении (REQ-REF-011, TC-O5).
    // Программный — чтобы IP встал в 0, а не в загрузчик
    pulse_rst(1'b0);

    //------------------------------------------------------------------
    $display("1. Execute looptest");
    for (int i = 0; (i < TEST_NUM) && !finished; i++) begin
        fetch_insn(code);

        case (code)
            4'h2: Data = Data + 12'd1;    // +
            4'h3: Data = Data - 12'd1;    // -
            4'h1: begin                   // HALT
                if (Data == 12'd0) begin
                    $display("HALT reached, Data = %0d at IP = %h",
                             Data, Address);
                    finished = 1;
                end
                else begin
                    errors++;
                    $display("FAIL: HALT with Data = %0d", Data);
                    finished = 1;
                end
            end
            default: ;                    // NOP, скобки, прочее
        endcase
    end

    if (!finished) begin
        errors++;
        $display("FAIL: program did not halt within %0d instructions", TEST_NUM);
    end

    //------------------------------------------------------------------
    $display("2. Load a program with nested loops, run with random loop_val_zero");
    prog_len = PROG_LEN;
    for (int i = 0; i < prog_len; i++) prog[i] = PROG[4*(PROG_LEN-1-i) +: 4];
    pulse_rst(1'b0);
    check_addr("soft reset", 0);
    Loading = 1'b1;
    for (int i = 0; i < prog_len; i++) begin
        load_insn(prog[i]);
        // Сквозная запись: insn — только что записанный опкод
        if (Insn !== prog[i] || InsnEot) begin
            errors++;
            $display("FAIL: load %0d: insn %h eot %b, expected %h", i, Insn, InsnEot, prog[i]);
        end
    end
    load_insn(4'hB);                    // LD = EOT: в память не пишется
    if (!InsnEot) begin
        errors++;
        $display("FAIL: EOT not reported (insn_eot %b)", InsnEot);
    end
    check_addr("EOT", prog_len);
    Loading = 1'b0;
    do_op();                            // любой запрос снимает insn_eot
    if (InsnEot) begin
        errors++;
        $display("FAIL: insn_eot still set after the next request");
    end
    for (int i = 0; i < prog_len; i++)
        if (mem.mem[i] !== prog[i]) begin
            errors++;
            $display("FAIL: mem[%0d] = %h, expected %h", i, mem.mem[i], prog[i]);
        end
    if (mem.mem[prog_len] !== 4'h0) begin
        errors++;
        $display("FAIL: EOT was written to memory");
    end

    pulse_rst(1'b0);
    rand_mode = 1'b1;
    seed = 32'h1DEC;
    ref_a = 0;
    scans = 0;
    fetch_insn(code);                   // первая выборка — без шага
    // Без break/continue: Icarus 12 (CI) их не поддерживает
    for (int i = 0; (i < RAND_NUM) && !stop; i++) begin
        if (bcd2bin(Address) !== ref_a || code !== prog[ref_a]) begin
            errors++;
            $display("FAIL: fetch %0d: IP %h insn %h, expected %0d insn %h",
                     i, Address, code, ref_a, prog[ref_a]);
            stop = 1;
        end
        else begin
            if (LoopCount !== '0 || LoopOverflow) begin
                errors++;
                $display("FAIL: loop counter %h / overflow %b after fetch %0d",
                         LoopCount, LoopOverflow, i);
            end
            z = $random(seed) & 1;
            nxt = ref_next(ref_a, code, z);
            if (nxt >= prog_len) nxt = -1;   // не уходить за конец
            if (nxt < 0) begin
                // Вернуться в начало
                pulse_rst(1'b0);
                fetch_insn(code);
                ref_a = 0;
            end
            else begin
                if (nxt != ref_a + 1) scans++;
                lvz_r = z;
                fetch_insn(code);
                ref_a = nxt;
            end
        end
    end
    rand_mode = 1'b0;
    $display("   %0d fetches, %0d scans", RAND_NUM, scans);
    if (scans < 20) begin
        errors++;
        $display("FAIL: too few scans");
    end

    //------------------------------------------------------------------
    $display("3. Loop counter overflow");
    for (int i = 0; i < 120; i++) mem.mem[i] = 4'h6;   // 120 x '['
    pulse_rst(1'b0);
    fetch_insn(code);                   // '[' по адресу 0
    rand_mode = 1'b1;
    lvz_r     = 1'b1;
    // Промотка вперёд, 100-я '[' — переполнение. После него IpLine до
    // сброса не отвечает (TC-N2): ready снят, IP стоит на скобке
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    ip_valid = 1'b1;
    @(posedge Clk);
    @(negedge Clk);
    ip_valid = 1'b0;
    for (int t = 0; t < 50000 && !LoopOverflow; t++) @(negedge Clk);
    if (!LoopOverflow || LoopCount !== 8'h99) begin
        errors++;
        $display("FAIL: overflow %b, loop count %h", LoopOverflow, LoopCount);
    end
    repeat (30) @(negedge Clk);
    check_addr("overflow stop", 99);
    if (ip_ready || !LoopOverflow) begin
        errors++;
        $display("FAIL: after overflow: ready %b overflow %b (IpLine must stand until reset)",
                 ip_ready, LoopOverflow);
    end
    pulse_rst(1'b0);                    // CLRL нет: снимает только сброс
    if (LoopOverflow || LoopCount !== '0) begin
        errors++;
        $display("FAIL: soft reset: overflow %b, loop count %h", LoopOverflow, LoopCount);
    end
    for (int i = 0; i < 120; i++) mem.mem[i] = 4'h0;

    //------------------------------------------------------------------
    $display("4. Soft reset: first fetch without a step");
    lvz_r = 1'b0;
    mem.mem[0] = 4'h2;
    mem.mem[1] = 4'h3;
    fetch_insn(code);
    fetch_insn(code);
    pulse_rst(1'b0);
    check_addr("soft reset", 0);
    fetch_insn(code);
    check_addr("fetch after soft reset", 0);
    if (code !== 4'h2) begin
        errors++;
        $display("FAIL: fetch after soft reset: %h", code);
    end
    fetch_insn(code);
    check_addr("next after soft reset", 1);

    //------------------------------------------------------------------
    $display("5. Halt and manual steps");
    mem.mem[3] = 4'h9;
    @(negedge Clk);
    HaltRq = 1'b1;
    repeat (20) @(negedge Clk);
    check_addr("halt step", 2);
    if (ip_ready) begin
        errors++;
        $display("FAIL: halt: ready %b", ip_ready);
    end
    key_step(1'b0);
    check_addr("key next", 3);
    key_step(1'b0);
    check_addr("key next", 4);
    key_step(1'b1);
    check_addr("key prev", 3);
    HaltRq = 1'b0;
    fetch_insn(code);
    check_addr("fetch after halt", 3);
    if (code !== 4'h9) begin
        errors++;
        $display("FAIL: fetch after halt: %h", code);
    end

    //------------------------------------------------------------------
    // Упреждающая выборка (P3): IP уже на следующей инструкции, при
    // останове шага нет, после пуска она же читается заново
    $display("5a. Halt with ip_ahead");
    @(negedge Clk);
    IpAhead = 1'b1;
    HaltRq  = 1'b1;
    repeat (20) @(negedge Clk);
    check_addr("halt ahead", 3);
    if (ip_ready) begin
        errors++;
        $display("FAIL: halt ahead: ready");
    end
    HaltRq  = 1'b0;
    IpAhead = 1'b0;
    fetch_insn(code);
    check_addr("fetch after halt ahead", 3);
    if (code !== 4'h9) begin
        errors++;
        $display("FAIL: fetch after halt ahead: %h", code);
    end
    fetch_insn(code);
    check_addr("next after halt ahead", 4);
    rand_mode = 1'b0;

    //------------------------------------------------------------------
    // Кнопки ±IP при загрузке (TC-N3): IpLine ждёт опкод в S_INSN_IN,
    // кнопка шагает счётчиком IP прямо оттуда, опкод пишется по новому IP
    $display("5b. Manual steps while loading");
    for (int i = 0; i < 4; i++) mem.mem[i] = 4'h0;   // остатки теста 2
    pulse_rst(1'b0);
    Loading = 1'b1;
    load_insn(4'h2);                    // адрес 0: первая выборка без шага
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    ip_valid = 1'b1;                    // запрос: шаг на 1, ожидание опкода
    @(posedge Clk);
    @(negedge Clk);
    ip_valid = 1'b0;
    repeat (10) @(negedge Clk);
    check_addr("loading, waiting", 1);
    key_step(1'b0);
    key_step(1'b0);
    key_step(1'b0);
    key_step(1'b1);
    check_addr("loading, keys", 3);
    InsnIn      = 4'h3;
    InsnInValid = 1'b1;
    while (!InsnInReady) @(negedge Clk);
    @(posedge Clk);
    @(negedge Clk);
    InsnInValid = 1'b0;
    InsnIn      = 4'hF;
    while (!ip_ready) @(negedge Clk);
    Loading = 1'b0;
    if (mem.mem[0] !== 4'h2 || mem.mem[1] !== 4'h0 ||
        mem.mem[2] !== 4'h0 || mem.mem[3] !== 4'h3) begin
        errors++;
        $display("FAIL: loading with keys: mem[0..3] = %h %h %h %h, expected 2 0 0 3",
                 mem.mem[0], mem.mem[1], mem.mem[2], mem.mem[3]);
    end

    //------------------------------------------------------------------
    $display("6. Hard reset");
    pulse_rst(1'b1);
    if (Address !== BOOTLOADER_ADDR) begin
        errors++;
        $display("FAIL: hard reset address %h, expected %h",
                 Address, BOOTLOADER_ADDR);
    end
    else begin
        $display("Hard reset sets IP = %h", Address);
    end

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us IpLine Test Success!");
    if (errors) $fatal(1, "IpLine test failed");
    $finish;
end

endmodule
