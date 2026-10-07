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
//   2. загрузка программы по insn_in (вложенные скобки, EOT, insn_eot) и её
//      выполнение со случайным loop_val_zero; каждая выборка
//      сравнивается с эталонной моделью (адрес и опкод), счётчик
//      вложенности после каждой выборки обязан быть нулём
//   3. переполнение счётчика вложенности, CLRL
//   4. CLRI: первая выборка без шага
//   5. останов: шаг IP, ручные шаги вперёд/назад, выборка без шага
//   6. аппаратный сброс: IP = 99900
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
reg hsClk;

initial begin
    hsClk = 1'b0;
    forever #50 hsClk = ~hsClk;
end

parameter TEST_NUM = 2000;
parameter RAND_NUM = 400;     // выборок в части 2

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

reg        ip_valid = 1'b0;
wire       ip_ready;
reg        ip_clr   = 1'b0;

// Операции теста. CLRI/CLRL IpLine различает по своему опкоду, поэтому
// тест кладёт его в регистр памяти модели перед clr
localparam [1:0] OP_NEXT = 2'd0, OP_CLR_IP = 2'd1, OP_CLR_LOOP = 2'd2;

wire       loop_val_zero;
wire [3:0] Insn;
wire       InsnValid;
wire       InsnEot;

reg        HaltRq    = 1'b0;
reg        KeyPrev   = 1'b0;
reg        KeyNext   = 1'b0;
reg        Loading   = 1'b0;
reg [3:0]  InsnIn    = 4'h0;
reg        InsnInValid = 1'b0;
wire       InsnInReady;

wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0]   Address;
wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount;
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
    .HARD_RST_D_CNT (IP_DEKATRON_NUM - 2),
    .LOOP_READ      (1'b1)
) ipLine (
    .rst_n        (Rst_n),
    .clk          (Clk),
    .hs_clk       (hsClk),
    .soft_rst     (SoftRst),
    .hard_rst     (HardRst),
    .valid        (ip_valid),
    .ready        (ip_ready),
    .clr          (ip_clr),
    .loop_val_zero(loop_val_zero),
    .insn         (Insn),
    .insn_valid   (InsnValid),
    .insn_eot     (InsnEot),
    .halt_rq      (HaltRq),
    .key_prev_ip  (KeyPrev),
    .key_next_ip  (KeyNext),
    .insn_loading (Loading),
    .insn_mode    (1'b0),          // Debug ISA: 0x4 — EOT
    .insn_in      (InsnIn),
    .insn_in_valid(InsnInValid),
    .insn_in_ready(InsnInReady),
    .ip_addr      (Address),
    .loop_count   (LoopCount),
    .loop_overflow(LoopOverflow),
    .mem_addr     (MemAddr),
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
    {4'd9, 4'd9, 4'd9, 4'd0, 4'd0};   // 99900 в BCD

initial begin $dumpfile("IpLine_tb.vcd"); $dumpvars(0, IpLine_tb); end

function automatic int bcd2bin(input [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] b);
    int r;
    r = 0;
    for (int i = IP_DEKATRON_NUM-1; i >= 0; i--)
        r = r*10 + b[4*i +: 4];
    return r;
endfunction

int errors = 0;

//----------------------------------------------------------------------
// Мониторы
//----------------------------------------------------------------------
always @(posedge Clk) begin
    if (Rst_n && MemValid && !MemReady) begin
        errors++;
        $display("FAIL: mem_valid without mem_ready");
    end
    if (Rst_n && ipLine.ip_valid && ipLine.loop_valid) begin
        errors++;
        $display("FAIL: ip_valid and loop_valid together");
    end
    if (Rst_n && ip_ready && InsnValid && ^Insn === 1'bx) begin
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
task automatic do_op(input [1:0] o);
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    // CLRI 0x9 / CLRL 0x8 — опкод текущей инструкции в регистре памяти
    if (o != OP_NEXT) begin
        mem.rd_data = (o == OP_CLR_IP) ? 4'h9 : 4'h8;
        poked       = 1;
    end
    ip_valid = 1'b1;
    ip_clr   = (o != OP_NEXT);
    @(posedge Clk);              // accept
    @(negedge Clk);
    ip_valid = 1'b0;
    ip_clr   = 1'b0;
    while (!ip_ready) @(negedge Clk);
endtask

//----------------------------------------------------------------------
// Один запрос следующей инструкции. Возвращает retired-опкод.
//----------------------------------------------------------------------
task automatic fetch_insn(output [3:0] code);
    do_op(OP_NEXT);
    while (!(ip_ready & InsnValid)) @(negedge Clk);
    code = Insn;
endtask

//----------------------------------------------------------------------
// Выборка в режиме загрузки: опкод уходит в память по текущему IP
//----------------------------------------------------------------------
task automatic load_insn(input [3:0] code);
    @(negedge Clk);
    while (!ip_ready) @(negedge Clk);
    ip_valid = 1'b1;
    ip_clr   = 1'b0;
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
    repeat (15) @(posedge Clk);    // 150 hs > RESET_MIN_HS = 100
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
// приводит НА парную скобку.
//----------------------------------------------------------------------
reg [3:0] prog [0:255];
int       prog_len;

function automatic int ref_next(input int a, input [3:0] c, input bit z);
    int depth;
    if (c == 4'h6 && z) begin
        depth = 0;
        for (int i = a; i < prog_len; i++) begin
            if (prog[i] == 4'h6) depth++;
            if (prog[i] == 4'h7) depth--;
            if (depth == 0) return i;
        end
        return -1;
    end
    if (c == 4'h7 && !z) begin
        depth = 0;
        for (int i = a; i >= 0; i--) begin
            if (prog[i] == 4'h7) depth++;
            if (prog[i] == 4'h6) depth--;
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

// [ + [ - [ ] ] . [ [ + ] - [ ] ] , ] + - [ + ]
localparam int PROG_LEN = 23;
localparam [4*PROG_LEN-1:0] PROG = 92'h62636778662736779723627;

initial begin
    Rst_n   <= 1'b0;
    HardRst <= 1'b0;
    SoftRst <= 1'b0;
    ip_valid<= 1'b0;
    ip_clr  <= 1'b0;
    Data    <= 12'd0;

    #2000 Rst_n <= 1'b1;
    while (!ip_ready) @(posedge Clk);

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
    load_insn(4'h4);                    // EOT: в память не пишется
    if (!InsnEot || !InsnValid) begin
        errors++;
        $display("FAIL: EOT not reported (insn_eot %b, insn_valid %b)", InsnEot, InsnValid);
    end
    check_addr("EOT", prog_len);
    Loading = 1'b0;
    do_op(OP_NEXT);                     // любая операция снимает insn_eot
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
                do_op(OP_CLR_IP);
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
    fetch_insn(code);                   // промотка вперёд, 100-я '[' — переполнение
    if (!LoopOverflow || LoopCount !== 8'h99) begin
        errors++;
        $display("FAIL: overflow %b, loop count %h", LoopOverflow, LoopCount);
    end
    check_addr("overflow stop", 99);
    fetch_insn(code);                   // счётчик на 99: снова переполнение без шага
    if (!LoopOverflow) begin
        errors++;
        $display("FAIL: overflow lost");
    end
    check_addr("overflow repeat", 99);
    do_op(OP_CLR_LOOP);
    if (LoopOverflow || LoopCount !== '0) begin
        errors++;
        $display("FAIL: CLRL: overflow %b, loop count %h", LoopOverflow, LoopCount);
    end
    for (int i = 0; i < 120; i++) mem.mem[i] = 4'h0;

    //------------------------------------------------------------------
    $display("4. CLRI");
    lvz_r = 1'b0;                       // текущая '[' — войти в тело, не мотать
    mem.mem[0] = 4'h2;
    mem.mem[1] = 4'h3;
    fetch_insn(code);
    do_op(OP_CLR_IP);
    check_addr("CLRI", 0);
    if (InsnValid) begin
        errors++;
        $display("FAIL: insn_valid after CLRI");
    end
    fetch_insn(code);
    check_addr("fetch after CLRI", 0);
    if (code !== 4'h2) begin
        errors++;
        $display("FAIL: fetch after CLRI: %h", code);
    end
    fetch_insn(code);
    check_addr("next after CLRI", 1);

    //------------------------------------------------------------------
    $display("5. Halt and manual steps");
    mem.mem[3] = 4'h9;
    @(negedge Clk);
    HaltRq = 1'b1;
    repeat (20) @(negedge Clk);
    check_addr("halt step", 2);
    if (ip_ready || InsnValid) begin
        errors++;
        $display("FAIL: halt: ready %b insn_valid %b", ip_ready, InsnValid);
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
    rand_mode = 1'b0;

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
