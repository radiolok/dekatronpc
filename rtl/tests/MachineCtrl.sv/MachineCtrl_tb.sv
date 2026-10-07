`timescale 1ns/1ps

//----------------------------------------------------------------------
// MachineCtrl_tb — тест верхнего автомата (REQ-CTLV2-*, TRS §22 п. 2)
//
// IpLine, ApLine, реле времени и терминал заменены моделями:
//   IpLine  выдаёт опкоды из очереди prog; пока очередь пуста, выборка
//           не заканчивается (автомат стоит в S_FETCH_W);
//   ApLine  занят 1..4 такта на операцию, проверяет, что op и dec
//           не меняются до возврата ready;
//   реле    по запросу поднимает линию сброса и busy на 6 тактов.
//
// Проверяется:
//   1. Таблица ISA: все 32 пары {insn_mode, insn} — какую операцию и
//      какому исполнителю выдаёт автомат, звонок, смена ISA, останов.
//   2. TEST перед скобкой только в BF и только при недостоверном
//      признаке нуля (REQ-CTLV2-007/008).
//   3. CIN: rx_rdy только по окончании операции CIN, эхо (REQ-UART-008).
//   4. Загрузка программы: SOT, ISA1/ISA0 внутри, EOT с SoftRstOnEOT.
//   5. HRST/SRST: набор команд после сброса, RunOnHardRst/RunOnSoftRst,
//      сброс с пульта во время операции (REQ-CTLV2-004/009).
//   6. Переполнение вложенности останавливает машину, звонок по ошибке,
//      повторный пуск не останавливается снова, после CLRL новое
//      переполнение снова останавливает (REQ-CTLV2-005).
//   7. Пошаговый режим, кнопка останова в S_IDLE и в ожидании CIN.
//
// Мониторы на каждом такте: valid без ready у IpLine и ApLine,
// одновременные ip_valid и ap_valid, rx_rdy вне конца CIN, запрос
// сброса обоих типов сразу.
//----------------------------------------------------------------------
module MachineCtrl_tb;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst_n = 1'b0;

// Состояния MachineCtrl
localparam [3:0]
    S_HALT     = 4'd0,
    S_IDLE     = 4'd1,
    S_DECODE   = 4'd4,
    S_CIN_WAIT = 4'd9;

localparam [1:0] IP_NEXT = 2'd0, IP_CLR_IP = 2'd1, IP_CLR_LOOP = 2'd2;

localparam [3:0]
    AP_NOP = 4'd0, AP_AP_STEP = 4'd1, AP_AP_ZERO = 4'd2, AP_DATA_STEP = 4'd3,
    AP_DATA_ZERO = 4'd4, AP_CIN = 4'd5, AP_COUT = 4'd6, AP_LOAD = 4'd7, AP_STORE = 4'd8,
    AP_CLRML = 4'd9, AP_TEST = 4'd10;

//----------------------------------------------------------------------
// Пульт и тумблеры
//----------------------------------------------------------------------
reg halt_key = 0, step_key = 0, run_key = 0;
reg key_load_start = 0, key_load_stop = 0;
reg echo_mode = 0, run_on_hard_rst = 0, run_on_soft_rst = 0, soft_rst_on_eot = 0;
reg bell_on_cin = 0, bell_on_halt = 0, bell_on_error = 0;

//----------------------------------------------------------------------
// DUT
//----------------------------------------------------------------------
wire       ip_valid;
wire       ip_ready;
wire [1:0] ip_op;
wire       loop_val_zero;
wire       insn_loading;
reg  [3:0] insn = 4'h0;
reg        insn_valid = 1'b0;
reg        loop_overflow = 1'b0;

wire       ap_valid;
wire       ap_ready;
wire [3:0] ap_op;
wire       ap_dec;
reg        data_zero = 1'b0;
reg        data_zero_valid = 1'b1;
reg        ap_zero = 1'b0;

wire       tx_vld;
reg        tx_rdy = 1'b0;
reg        rx_vld = 1'b0;
wire       rx_rdy;

wire       soft_rst_req, hard_rst_req;
reg        rst_busy = 1'b0;
reg        soft_rst = 1'b0, hard_rst = 1'b0;

wire        insn_mode, is_halted, bell;
wire [3:0]  state;
wire [31:0] iret;

MachineCtrl #(.EN_EMULATOR(1'b1)) dut (
    .clk(clk), .rst_n(rst_n),
    .halt_key(halt_key), .step_key(step_key), .run_key(run_key),
    .key_insn_loading_start(key_load_start), .key_insn_loading_stop(key_load_stop),
    .echo_mode(echo_mode), .run_on_hard_rst(run_on_hard_rst),
    .run_on_soft_rst(run_on_soft_rst), .soft_rst_on_eot(soft_rst_on_eot),
    .bell_on_cin(bell_on_cin), .bell_on_halt(bell_on_halt), .bell_on_error(bell_on_error),
    .ip_valid(ip_valid), .ip_ready(ip_ready), .ip_op(ip_op),
    .loop_val_zero(loop_val_zero), .insn_loading(insn_loading),
    .insn(insn), .insn_valid(insn_valid), .loop_overflow(loop_overflow),
    .ap_valid(ap_valid), .ap_ready(ap_ready), .ap_op(ap_op), .ap_dec(ap_dec),
    .data_zero(data_zero), .data_zero_valid(data_zero_valid), .ap_zero(ap_zero),
    .mem_lock(1'b0),
    .tx_vld(tx_vld), .tx_rdy(tx_rdy), .rx_vld(rx_vld), .rx_rdy(rx_rdy),
    .soft_rst_req(soft_rst_req), .hard_rst_req(hard_rst_req), .rst_busy(rst_busy),
    .soft_rst(soft_rst), .hard_rst(hard_rst),
    .insn_mode(insn_mode), .is_halted(is_halted), .bell(bell),
    .state(state), .iret(iret)
);

integer errors = 0;

task automatic fail(input string msg);
    errors++;
    $display("%0t FAIL: %s", $time, msg);
endtask

//----------------------------------------------------------------------
// Модель IpLine
//----------------------------------------------------------------------
reg [3:0] prog [$];
integer   ip_busy = 0;
reg       ip_fetching = 1'b0;   // выборка принята, ждём опкод
reg       ovf_on_fetch = 1'b0;  // следующая выборка кончится переполнением

// Как в IpLine: ready не зависит от valid, при останове снят
assign ip_ready = (ip_busy == 0) & ~ip_fetching & ~is_halted & ~(soft_rst | hard_rst);

// Счётчики выданных операций
integer n_ip [0:3];
integer n_ap [0:15];
reg     last_ap_dec;
integer n_tx, n_bell, n_hreq, n_sreq, n_rx;

task automatic clear_counts();
    for (int i = 0; i < 4;  i++) n_ip[i] = 0;
    for (int i = 0; i < 16; i++) n_ap[i] = 0;
    n_tx = 0; n_bell = 0; n_hreq = 0; n_sreq = 0; n_rx = 0;
endtask

always @(posedge clk) begin
    if (soft_rst | hard_rst) begin
        ip_busy     <= 0;
        ip_fetching <= 1'b0;
        insn_valid  <= 1'b0;
    end
    else begin
        if (ip_busy > 0) ip_busy <= ip_busy - 1;

        if (ip_valid & ip_ready) begin
            n_ip[ip_op] = n_ip[ip_op] + 1;
            case (ip_op)
                IP_NEXT:     ip_fetching <= 1'b1;
                IP_CLR_LOOP: begin ip_busy <= 2; loop_overflow <= 1'b0; end
                IP_CLR_IP:   begin ip_busy <= 2; insn_valid <= 1'b0; end
                default:     fail("ip_op 3");
            endcase
        end

        if (ip_fetching & (ip_busy == 0)) begin
            if (ovf_on_fetch) begin
                // Промотка прервана переполнением: IpLine готов, опкод
                // прежний (скобка), признак переполнения поднят
                ovf_on_fetch  <= 1'b0;
                loop_overflow <= 1'b1;
                ip_fetching   <= 1'b0;
            end
            else if (prog.size() > 0) begin
                insn        <= prog.pop_front();
                insn_valid  <= 1'b1;
                ip_fetching <= 1'b0;
                ip_busy     <= 1;
            end
        end
    end
end

//----------------------------------------------------------------------
// Модель ApLine
//----------------------------------------------------------------------
integer   ap_busy = 0;
reg [3:0] ap_op_q;
reg       ap_dec_q;

assign ap_ready = (ap_busy == 0) & ~(soft_rst | hard_rst);

always @(posedge clk) begin
    if (soft_rst | hard_rst) begin
        ap_busy <= 0;
    end
    else begin
        if (ap_busy > 0) begin
            ap_busy <= ap_busy - 1;
            // op и dec держит мастер до ready
            if (ap_op !== ap_op_q)
                fail($sformatf("ap_op changed while ApLine busy: %0d -> %0d", ap_op_q, ap_op));
            if ((ap_op_q == AP_DATA_STEP || ap_op_q == AP_AP_STEP) && ap_dec !== ap_dec_q)
                fail("ap_dec changed while ApLine busy");
        end
        if (ap_valid & ap_ready) begin
            n_ap[ap_op] = n_ap[ap_op] + 1;
            last_ap_dec = ap_dec;
            ap_op_q  <= ap_op;
            ap_dec_q <= ap_dec;
            ap_busy  <= 1 + ($urandom % 4);
        end
    end
end

//----------------------------------------------------------------------
// Реле времени
//----------------------------------------------------------------------
reg panel_soft = 1'b0, panel_hard = 1'b0;
integer relay_cnt = 0;

always @(posedge clk) begin
    if (relay_cnt > 0) begin
        relay_cnt <= relay_cnt - 1;
        if (relay_cnt == 1) begin
            rst_busy <= 1'b0;
            soft_rst <= 1'b0;
            hard_rst <= 1'b0;
        end
    end
    else if (soft_rst_req | hard_rst_req | panel_soft | panel_hard) begin
        relay_cnt <= 6;
        rst_busy  <= 1'b1;
        hard_rst  <= hard_rst_req | panel_hard;
        soft_rst  <= ~(hard_rst_req | panel_hard);
    end
end

//----------------------------------------------------------------------
// Терминал и счётчики событий
//----------------------------------------------------------------------
reg in_cin_op = 1'b0;   // ApLine выполняет CIN

always @(posedge clk) begin
    if (rst_n) begin
        if (tx_vld & tx_rdy) n_tx++;
        if (bell)            n_bell++;
        if (hard_rst_req & ~rst_busy) n_hreq++;
        if (soft_rst_req & ~rst_busy) n_sreq++;
        if (rx_vld & rx_rdy) begin
            n_rx++;
            rx_vld <= 1'b0;
        end

        if (ap_valid & ap_ready & (ap_op == AP_CIN)) in_cin_op <= 1'b1;
        if (rx_vld & rx_rdy)                         in_cin_op <= 1'b0;

        // Мониторы
        if (ip_valid & ~ip_ready) fail("ip_valid without ip_ready");
        if (ap_valid & ~ap_ready) fail("ap_valid without ap_ready");
        if (ip_valid & ap_valid)  fail("ip_valid and ap_valid together");
        if (soft_rst_req & hard_rst_req) fail("soft and hard reset requests together");
        if (rx_rdy & ~(in_cin_op & ap_ready))
            fail("rx_rdy before CIN finished");
        if (rx_rdy & ~rx_vld) fail("rx_rdy without a pending character");
        // Выводится счётчик данных: пока ApLine его пишет, вывода нет
        if (tx_vld & ~ap_ready) fail("tx_vld while ApLine busy");
    end
end

//----------------------------------------------------------------------
// Вспомогательные задачи
//----------------------------------------------------------------------
task automatic tick(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
endtask

// Машина ждёт опкод: выборка принята, очередь пуста, ApLine свободен.
// Код состояния не проверяется, чтобы тест годился и прежнему автомату
function automatic bit parked();
    return ip_fetching && (prog.size() == 0) && ap_ready && !is_halted;
endfunction

// Автомат дошёл до точки покоя: стоит, ждёт опкод или ввод
function automatic bit settled();
    return (state == S_HALT) || (state == S_CIN_WAIT) || parked();
endfunction

task automatic wait_settled(input string what);
    int t = 0;
    tick(2);
    // Точка покоя должна продержаться: S_DECODE проходит её за такт
    for (int stable = 0; stable < 3 && t < 2000; t++) begin
        tick();
        stable = settled() ? stable + 1 : 0;
    end
    if (t >= 2000) fail({"timeout: ", what});
endtask

task automatic run_from_halt();
    if (state != S_HALT) fail("run_from_halt: not halted");
    run_key = 1'b1; tick(3);
    run_key = 1'b0; tick(2);
endtask

// Исполнить один опкод из точки покоя S_FETCH_W
task automatic exec(input [3:0] op);
    clear_counts();
    prog.push_back(op);
    wait_settled($sformatf("exec %h mode %b", op, insn_mode));
endtask

task automatic set_mode(input bit m);
    if (insn_mode !== m) exec(m ? 4'hF : 4'hE);
    if (insn_mode !== m) fail("set_mode");
endtask

task automatic expect_only(input string what, input int ipop, input int apop, input int tx, input int bells);
    int ap_total = 0;
    for (int i = 0; i < 16; i++) ap_total += n_ap[i];
    // IP_NEXT не считаем: это выборка следующей инструкции
    for (int i = 1; i < 4; i++)
        if (n_ip[i] != ((i == ipop) ? 1 : 0))
            fail($sformatf("%s: ip op %0d issued %0d times", what, i, n_ip[i]));
    if (apop < 0 && ap_total != 0)
        fail($sformatf("%s: unexpected ap op (total %0d)", what, ap_total));
    if (apop >= 0 && (n_ap[apop] != 1 || ap_total != 1))
        fail($sformatf("%s: ap op %0d issued %0d times (total %0d)", what, apop, n_ap[apop], ap_total));
    if (n_tx != tx)
        fail($sformatf("%s: tx %0d, expected %0d", what, n_tx, tx));
    if (n_bell != bells)
        fail($sformatf("%s: bell %0d, expected %0d", what, n_bell, bells));
    if (n_hreq != 0 || n_sreq != 0)
        fail($sformatf("%s: unexpected reset request", what));
endtask

// Холодный старт: rst_n, сброс реле при включении не моделируется
task automatic power_up();
    rst_n = 1'b0;
    prog.delete();
    tick(3);
    rst_n = 1'b1;
    tick(2);
    if (state != S_HALT) fail("after rst_n: not in S_HALT");
    if (insn_mode !== 1'b0) fail("after rst_n: not Debug ISA");
    run_from_halt();
    wait_settled("power_up");
endtask

//----------------------------------------------------------------------
// 1, 2. Таблица ISA
//----------------------------------------------------------------------
task automatic check_isa_table();
    $display("check_isa_table");
    tx_rdy = 1'b1;

    for (int m = 0; m < 2; m++) begin
        for (int op = 0; op < 16; op++) begin
            string what = $sformatf("{%0d,%h}", m, op);
            bit was_mode;
            // {x,1}/{x,5}/{x,C}/{x,D} — ниже, CIN — отдельно (без continue: Icarus 12)
            if (!(op == 4'h1 || op == 4'h5 || op == 4'hC || op == 4'hD || (m == 1 && op == 4'h9))) begin
                set_mode(m);
                was_mode = insn_mode;
                data_zero_valid = 1'b1;
                exec(op[3:0]);
                if (!parked()) fail({what, ": machine stopped"});
                case ({m[0], op[3:0]})
                    5'h02: expect_only(what, -1, -1, 0, 1);              // BELL
                    5'h08: expect_only(what, IP_CLR_LOOP, -1, 0, 0);     // CLRL
                    5'h09: expect_only(what, IP_CLR_IP, -1, 0, 0);       // CLRI
                    5'h0A: expect_only(what, -1, AP_DATA_ZERO, 0, 0);    // CLRD
                    5'h0B: expect_only(what, -1, AP_AP_ZERO, 0, 0);      // CLRA
                    5'h12, 5'h13: begin                                  // + -
                        expect_only(what, -1, AP_DATA_STEP, 0, 0);
                        if (last_ap_dec !== op[0]) fail({what, ": dec"});
                    end
                    5'h14, 5'h15: begin                                  // > <
                        expect_only(what, -1, AP_AP_STEP, 0, 0);
                        if (last_ap_dec !== op[0]) fail({what, ": dec"});
                    end
                    5'h18: expect_only(what, -1, AP_COUT, 1, 0);         // . (OPEN-017)
                    5'h1A: expect_only(what, -1, AP_DATA_ZERO, 0, 0);    // [-]
                    5'h1B: expect_only(what, -1, AP_CLRML, 0, 0);
                    5'h1C: expect_only(what, -1, AP_LOAD, 0, 0);
                    5'h1D: expect_only(what, -1, AP_STORE, 0, 0);
                    default: expect_only(what, -1, -1, 0, 0);            // NOP, скобки, ISA, EOT, 0x3
                endcase
                // Смена набора команд
                if (op == 4'hE && insn_mode !== 1'b0) fail({what, ": ISA0"});
                if (op == 4'hF && insn_mode !== 1'b1) fail({what, ": ISA1"});
                if (op != 4'hE && op != 4'hF && insn_mode !== was_mode) fail({what, ": mode changed"});
            end
        end
    end

    // Скобки в BF при недостоверном признаке: одна операция TEST
    set_mode(1);
    for (int op = 6; op < 8; op++) begin
        data_zero_valid = 1'b0;
        exec(op[3:0]);
        expect_only($sformatf("BF bracket %h, zero invalid", op), -1, AP_TEST, 0, 0);
    end
    // В Debug TEST не выдаётся никогда
    set_mode(0);
    for (int op = 6; op < 8; op++) begin
        data_zero_valid = 1'b0;
        exec(op[3:0]);
        expect_only($sformatf("Debug bracket %h", op), -1, -1, 0, 0);
    end
    data_zero_valid = 1'b1;

    // loop_val_zero: в BF — ячейка, в Debug — адрес
    data_zero = 1'b1; ap_zero = 1'b0; #1;
    if (loop_val_zero !== 1'b0) fail("loop_val_zero in Debug must follow ap_zero");
    set_mode(1);
    #1;
    if (loop_val_zero !== 1'b1) fail("loop_val_zero in BF must follow data_zero");
    data_zero = 1'b0;

    // HALT в обоих наборах, со звонком
    bell_on_halt = 1'b1;
    for (int m = 0; m < 2; m++) begin
        set_mode(m);
        exec(4'h1);
        if (state != S_HALT) fail($sformatf("HALT mode %0d: not halted", m));
        if (n_bell != 1) fail($sformatf("HALT mode %0d: bell %0d", m, n_bell));
        run_from_halt();
        wait_settled("after HALT");
    end
    bell_on_halt = 1'b0;
endtask

//----------------------------------------------------------------------
// 3. CIN
//----------------------------------------------------------------------
task automatic check_cin();
    $display("check_cin");
    set_mode(1);
    tx_rdy = 1'b1;
    for (int e = 0; e < 2; e++) begin
        echo_mode   = e;
        bell_on_cin = 1'b1;
        exec(4'h9);
        if (state != S_CIN_WAIT) fail("CIN: not waiting");
        if (n_bell != 1) fail("CIN: bell_on_cin");
        if (n_ap[AP_CIN] != 0) fail("CIN: AP_CIN before rx_vld");
        tick(10);
        if (state != S_CIN_WAIT) fail("CIN: left S_CIN_WAIT without rx_vld");
        rx_vld = 1'b1;
        wait_settled("CIN done");
        if (rx_vld)            fail("CIN: no rx handshake");
        if (n_rx != 1)         fail("CIN: rx handshakes");
        if (n_ap[AP_CIN] != 1) fail("CIN: AP_CIN count");
        if (n_tx != e)         fail($sformatf("CIN: echo %0d, expected %0d", n_tx, e));
    end
    bell_on_cin = 1'b0;
    echo_mode   = 1'b0;

    // Останов во время ожидания символа
    exec(4'h9);
    halt_key = 1'b1; tick(3);
    halt_key = 1'b0; tick(2);
    if (state != S_HALT) fail("CIN: halt_key ignored");
    if (n_ap[AP_CIN] != 0) fail("CIN: AP_CIN after halt");
    run_from_halt();
    wait_settled("after CIN halt");
endtask

//----------------------------------------------------------------------
// 4. Загрузка программы
//----------------------------------------------------------------------
task automatic check_loading();
    $display("check_loading");
    set_mode(0);
    soft_rst_on_eot = 1'b0;
    exec(4'h5);                                   // SOT
    if (!insn_loading) fail("SOT: loading not set");
    // В загрузке ничего не исполняется
    for (int op = 0; op < 16; op++) begin
        if (op != 4 && op != 4'hE && op != 4'hF) begin
            exec(op[3:0]);
            expect_only($sformatf("loading %h", op), -1, -1, 0, 0);
            if (!parked()) fail($sformatf("loading %h: stopped", op));
        end
    end
    // ISA1 внутри загрузки: 0x4 — уже '>', а не EOT
    exec(4'hF);
    exec(4'h4);
    if (!insn_loading) fail("loading: 0x4 in BF ended the load");
    exec(4'hE);
    exec(4'h4);                                   // EOT
    if (insn_loading)     fail("EOT: loading still set");
    if (state != S_HALT)  fail("EOT without SoftRstOnEOT: not halted");
    if (n_sreq != 0)      fail("EOT without SoftRstOnEOT: reset requested");

    // EOT с программным сбросом и автозапуском
    soft_rst_on_eot = 1'b1;
    run_on_soft_rst = 1'b1;
    run_from_halt();
    wait_settled("before SOT");
    exec(4'h5);
    exec(4'h2);
    clear_counts();
    prog.push_back(4'h4);
    wait_settled("EOT soft reset");
    if (n_sreq != 1)          fail("EOT: no soft reset request");
    if (insn_mode !== 1'b1)   fail("EOT: not BF after soft reset");
    if (!parked())   fail("EOT: RunOnSoftRst did not start the program");
    soft_rst_on_eot = 1'b0;
    run_on_soft_rst = 1'b0;

    // Загрузка с пульта и её прерывание
    exec(4'h1);
    if (state != S_HALT) fail("loading key: not halted");
    key_load_start = 1'b1; tick(3); key_load_start = 1'b0;
    wait_settled("load key");
    if (!insn_loading) fail("loading key: loading not set");
    key_load_stop = 1'b1;
    exec(4'h2);
    key_load_stop = 1'b0;
    if (insn_loading)    fail("loading stop key: loading still set");
    if (state != S_HALT) fail("loading stop key: not halted");
    run_from_halt();
    wait_settled("after load stop");
endtask

//----------------------------------------------------------------------
// 5. Сбросы
//----------------------------------------------------------------------
task automatic check_resets();
    $display("check_resets");
    // HRST из BF невозможен (0xC — LOAD), поэтому из Debug
    for (int r = 0; r < 2; r++) begin
        set_mode(0);
        run_on_hard_rst = r;
        clear_counts();
        prog.push_back(4'hC);
        wait_settled("HRST");
        if (n_hreq != 1)        fail("HRST: no hard request");
        if (n_sreq != 0)        fail("HRST: soft request");
        if (insn_mode !== 1'b0) fail("HRST: not Debug ISA");
        if (r == 0 && state != S_HALT)    fail("HRST: RunOnHardRst=0 but running");
        if (r == 1 && !parked()) fail("HRST: RunOnHardRst=1 but halted");
        if (r == 0) begin run_from_halt(); wait_settled("after HRST"); end
    end
    run_on_hard_rst = 1'b0;

    for (int r = 0; r < 2; r++) begin
        set_mode(0);
        run_on_soft_rst = r;
        clear_counts();
        prog.push_back(4'hD);
        wait_settled("SRST");
        if (n_sreq != 1)        fail("SRST: no soft request");
        if (insn_mode !== 1'b1) fail("SRST: not BF ISA");
        if (r == 0 && state != S_HALT)    fail("SRST: RunOnSoftRst=0 but running");
        if (r == 1 && !parked()) fail("SRST: RunOnSoftRst=1 but halted");
        if (r == 0) begin run_from_halt(); wait_settled("after SRST"); end
    end
    run_on_soft_rst = 1'b0;

    // Сброс с пульта во время ожидания ввода: машина бросает CIN
    set_mode(1);
    exec(4'h9);
    if (state != S_CIN_WAIT) fail("panel reset: not in CIN");
    panel_hard = 1'b1; tick(); panel_hard = 1'b0;
    wait_settled("panel hard reset");
    if (state != S_HALT)    fail("panel hard reset: not halted");
    if (insn_mode !== 1'b0) fail("panel hard reset: not Debug ISA");
    run_from_halt();
    wait_settled("after panel reset");

    // Сброс с пульта во время загрузки снимает её
    exec(4'h5);
    panel_soft = 1'b1; tick(); panel_soft = 1'b0;
    wait_settled("panel soft reset");
    if (insn_loading)       fail("panel soft reset: loading still set");
    if (insn_mode !== 1'b1) fail("panel soft reset: not BF ISA");
    run_from_halt();
    wait_settled("after panel soft reset");
endtask

//----------------------------------------------------------------------
// 6. Переполнение вложенности
//----------------------------------------------------------------------
task automatic check_overflow();
    int iret0;
    $display("check_overflow");
    set_mode(1);
    bell_on_error = 1'b1;
    // Как в IpLine: insn держит скобку, на которой прервана промотка,
    // insn_valid поднят
    exec(4'h7);
    clear_counts();
    iret0 = iret;
    ovf_on_fetch = 1'b1;
    tick(20);
    wait_settled("overflow");
    if (state != S_HALT) fail("overflow: not halted");
    if (n_bell != 1)     fail("overflow: no bell");
    if (iret != iret0)   fail("overflow: the bracket was decoded");
    // Пуск: признак ещё поднят, но второй раз машина не встаёт
    run_from_halt();
    wait_settled("run after overflow");
    exec(4'h2);
    if (!parked()) fail("overflow: halted again without a new overflow");
    // CLRL снимает признак, новое переполнение снова останавливает
    set_mode(0);
    exec(4'h8);
    if (loop_overflow) fail("CLRL: overflow not cleared");
    exec(4'h7);
    ovf_on_fetch = 1'b1;
    tick(20);
    wait_settled("second overflow");
    if (state != S_HALT) fail("second overflow after CLRL: not halted");
    exec(4'h8);    // в останове выборка не идёт: опкод останется в очереди
    run_from_halt();
    wait_settled("after second overflow");
    bell_on_error = 1'b0;
endtask

//----------------------------------------------------------------------
// 7. Пошаговый режим и кнопка останова
//----------------------------------------------------------------------
task automatic check_step_halt();
    int iret0;
    $display("check_step_halt");
    set_mode(1);
    bell_on_halt = 1'b1;
    clear_counts();
    // Кнопка останова действует в S_IDLE, то есть по окончании текущей
    // инструкции: держим её, пока исполняется NOP
    halt_key = 1'b1;
    prog.push_back(4'h0);
    wait_settled("halt key");
    halt_key = 1'b0;
    tick(2);
    if (state != S_HALT) fail("halt key: not halted");
    if (n_bell != 1)     fail("halt key: bell_on_halt");
    bell_on_halt = 1'b0;

    // Каждое нажатие шага — ровно одна инструкция, в том числе с
    // операцией над ApLine и с выводом
    tx_rdy = 1'b1;
    for (int i = 0; i < 3; i++) begin
        prog.push_back(4'h2);
        prog.push_back(4'h8);
    end
    for (int i = 0; i < 6; i++) begin
        iret0 = iret;
        step_key = 1'b1;
        tick(30);                 // держим кнопку: второй шаг не идёт
        if (iret != iret0 + 1) fail($sformatf("step %0d: %0d instructions", i, iret - iret0));
        if (state != S_HALT)   fail($sformatf("step %0d: not halted", i));
        step_key = 1'b0;
        tick(3);
    end
    if (prog.size() != 0) fail("step: program not consumed");
    run_from_halt();
    wait_settled("after step");
endtask

//----------------------------------------------------------------------
initial begin
    $dumpfile("MachineCtrl_tb.vcd");
    $dumpvars(0, MachineCtrl_tb);
    clear_counts();

    power_up();
    check_isa_table();
    check_cin();
    check_loading();
    check_resets();
    check_overflow();
    check_step_halt();

    if (errors) begin
        $display("%0t MachineCtrl Test FAILED, errors=%0d", $time, errors);
        $fatal(1, "MachineCtrl test failed");
    end
    $display("%0t MachineCtrl Test Success!", $time);
    $finish;
end

initial begin
    #5000000;
    $display("TIMEOUT");
    $fatal(1, "MachineCtrl test timeout");
end

endmodule
