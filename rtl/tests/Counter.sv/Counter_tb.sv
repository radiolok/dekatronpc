`timescale 1ns/1ps

//----------------------------------------------------------------------
// Counter_tb — тест DekatronCounter (Valid/Ready)
//
// [TRS v0.24] Такт 100 кГц (HS_PER_CLK = HSCLK_DIV): любая операция —
// шаг, запись, сброс в нуль, переход через край — завершается в такте
// рукопожатия, ready снимают только линии сброса. Тест «подряд» выдаёт
// операции каждый такт без пауз и проверяет показание на каждом фронте:
// после записи сразу шаг с переносом, после set_zero сразу декремент
// через край — признаки nines_q/zeroes_q/zero_q/at_top_q обязаны быть
// защёлкнуты с уже записанного значения.
//
// Второй счётчик ip_counter собран как IP (5 декад, без записи,
// HARD_RST_D_CNT = 3): аппаратный сброс даёт 99900, программный — 0.
// На нетлисте (`NETLIST_SIM, synth_sim.sh) его нет: синтезирован только
// счётчик с параметрами основного DUT.
//
// `define DEKATRON_RANDOM_INIT (EMUL_DEFINES): декатроны зажигаются на
// случайных катодах, как при включении питания. Тест начинается со
// сброса по линиям hard_rst/soft_rst и проверяет, что он приводит оба
// счётчика в известное состояние (doc/harwell_1951_review.md §3).
//----------------------------------------------------------------------
module Counter_tb #(
    parameter DEKATRON_NUM = 3
);

localparam WIDTH    = DEKATRON_NUM*4;
localparam TEST_NUM = 50;
localparam TOP      = 255;

reg Rst_n;
reg Clk;
`ifndef DEKATRON_DELAY_MODEL
reg hsClk;
`endif
`ifdef DEKATRON_DELAY_MODEL
// Период Clk в нс (synth_sim.sh -c): поиск частоты, на которой работает
// нетлист с задержками ламп (doc/vtube_sdf_timing.md)
`ifndef CLK_NS
`define CLK_NS CLK_PERIOD_NS
`endif
// Модель на задержках: hsClk нет вовсе [TRS v0.25]. Clk с той же фазой,
// что дал бы делитель: первый фронт через 50 нс после снятия Rst_n.
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

reg             valid   = 1'b0;
reg             Dec     = 1'b0;
reg             Set     = 1'b0;
reg             SetZero = 1'b0;
reg             soft_rst= 1'b0;
reg             hard_rst= 1'b0;
reg [WIDTH-1:0] In      = '0;

wire             Ready;
wire [WIDTH-1:0] Out;
wire [WIDTH-1:0] Out_n;          // тетрады счётчика — активным нулём (TC-O3)
assign Out = ~Out_n;
wire             Zero;
wire             AtTop;

DekatronCounter  #(.D_NUM(DEKATRON_NUM),
                    .TOP_LIMIT_MODE(1'b1),
                    .TOP_VALUE({4'd2, 4'd5, 4'd5})
)counter(
    .rst_n    (Rst_n),
    .clk      (Clk),
`ifndef DEKATRON_DELAY_MODEL
    .hs_clk   (hsClk),
`endif
    .soft_rst (soft_rst),
    .hard_rst (hard_rst),
    .valid    (valid),
    .ready    (Ready),
    .dec      (Dec),
    .set      (Set),
    .set_zero (SetZero),
    .in_n     (~In),
    .out_n    (Out_n),
    .zero     (Zero),
    .at_top   (AtTop)
);

// Счётчик в конфигурации IP: только сбросы, без операций
localparam IP_NUM   = 5;
localparam IP_WIDTH = IP_NUM*4;

wire                IpReady;
wire [IP_WIDTH-1:0] IpOut;

`ifdef NETLIST_SIM
assign IpReady = 1'b1;
assign IpOut   = '0;
`else
wire [IP_WIDTH-1:0] IpOut_n;
assign IpOut = ~IpOut_n;
DekatronCounter  #(.D_NUM(IP_NUM),
                    .WRITE(1'b0),
                    .TOP_LIMIT_MODE(1'b0),
                    .HARD_RST_D_CNT(IP_NUM-2)
)ip_counter(
    .rst_n    (Rst_n),
    .clk      (Clk),
`ifndef DEKATRON_DELAY_MODEL
    .hs_clk   (hsClk),
`endif
    .soft_rst (soft_rst),
    .hard_rst (hard_rst),
    .valid    (1'b0),
    .ready    (IpReady),
    .dec      (1'b0),
    .set      (1'b0),
    .set_zero (1'b0),
    .in_n     ({IP_WIDTH{1'b1}}),
    .out_n    (IpOut_n),
    .zero     (),
    .at_top   ()
);
`endif

//----------------------------------------------------------------------
// Одна быстрая операция (инкремент/декремент).
// valid выставляется по фронту clk и держится ровно один такт: только
// так StepF/StepR покрывает весь такт вместе с обеими фазами.
//----------------------------------------------------------------------
task automatic do_op_full(input bit d, input bit s, input bit sz,
                         input [WIDTH-1:0] v);
    while (!Ready) @(posedge Clk);
    @(posedge Clk);
    valid   <= 1'b1;
    Dec     <= d;
    Set     <= s;
    SetZero <= sz;
    In      <= v;
    @(posedge Clk);
    valid   <= 1'b0;
    Set     <= 1'b0;
    SetZero <= 1'b0;
    // Любая операция завершается к фронту после такта рукопожатия
    // [TRS v0.24]; ready снимают только линии сброса
    @(posedge Clk);
    while (!Ready) @(posedge Clk);
    @(posedge Clk);          // дать признакам zero/at_top установиться
endtask

task automatic do_op(input bit d);
    do_op_full(d, 1'b0, 1'b0, {WIDTH{1'b0}});
endtask

//----------------------------------------------------------------------
// Физический сброс: линия держится заметно дольше WRITE_MIN_HS.
//----------------------------------------------------------------------
task automatic do_rst(input bit hard, input bit expected_top);
    @(posedge Clk);
    soft_rst <= ~hard;
    hard_rst <=  hard;
    repeat (3) @(posedge Clk);        // реле времени: 3 такта > WRITE_MIN_HS
    soft_rst <= 1'b0;
    hard_rst <= 1'b0;
    @(posedge Clk);
    while (!Ready || !IpReady) @(posedge Clk);
endtask

function automatic [WIDTH-1:0] exp_to_bcd(input int unsigned v);
    exp_to_bcd = {4'((v/100)%10), 4'((v/10)%10), 4'(v%10)};
endfunction

int errors = 0;
int exp_val;

//----------------------------------------------------------------------
// Операции подряд, по одной на такт: valid не снимается между ними.
// Показание проверяется на фронте, завершающем такт операции.
//----------------------------------------------------------------------
localparam int B2B_N = 14;

// Шаг i: {код операции, аргумент записи, ожидаемое показание}.
// Код: 0 — инкремент, 1 — декремент, 2 — запись, 3 — set_zero
task automatic b2b(input int i, output int op, output int arg,
                   output int exp_v);
    case (i)
        0:  begin op = 2; arg = 199; exp_v = 199; end  // запись
        1:  begin op = 0; arg = 0;   exp_v = 200; end  // перенос через две декады
        2:  begin op = 1; arg = 0;   exp_v = 199; end  // заём через две декады
        3:  begin op = 3; arg = 0;   exp_v = 0;   end  // set_zero
        4:  begin op = 1; arg = 0;   exp_v = 255; end  // 0 - 1 -> TOP сразу после set_zero
        5:  begin op = 0; arg = 0;   exp_v = 0;   end  // TOP + 1 -> 0 сразу после перехода
        6:  begin op = 0; arg = 0;   exp_v = 1;   end
        7:  begin op = 2; arg = 9;   exp_v = 9;   end
        8:  begin op = 0; arg = 0;   exp_v = 10;  end
        9:  begin op = 1; arg = 0;   exp_v = 9;   end
        10: begin op = 2; arg = 100; exp_v = 100; end
        11: begin op = 1; arg = 0;   exp_v = 99;  end
        12: begin op = 0; arg = 0;   exp_v = 100; end
        default: begin op = 0; arg = 0; exp_v = 101; end
    endcase
endtask

task automatic back_to_back();
    int op, arg, exp_v;
    while (!Ready) @(posedge Clk);
    for (int i = 0; i < B2B_N; i++) begin
        b2b(i, op, arg, exp_v);
        valid   <= 1'b1;
        Dec     <= (op == 1);
        Set     <= (op == 2);
        SetZero <= (op == 3);
        In      <= exp_to_bcd(arg);
        @(posedge Clk);
        if (!Ready) begin
            errors++;
            $display("FAIL: ready dropped in back-to-back op %0d at %0t", i, $time);
        end
        if (Out !== exp_to_bcd(exp_v)) begin
            errors++;
            $display("FAIL: back-to-back op %0d (code %0d): Out=%h expected=%h at %0t",
                     i, op, Out, exp_to_bcd(exp_v), $time);
        end
    end
    valid   <= 1'b0;
    Set     <= 1'b0;
    SetZero <= 1'b0;
    @(posedge Clk);
endtask

task automatic check_ip(input [IP_WIDTH-1:0] v);
`ifndef NETLIST_SIM
    if (IpOut !== v) begin
        errors++;
        $display("FAIL: IpOut=%h expected=%h at %0t", IpOut, v, $time);
    end
`endif
endtask

task automatic check_out(input int unsigned v);
    exp_val = v % (TOP+1);
    if (Out !== exp_to_bcd(exp_val)) begin
        errors++;
        $display("FAIL: Out=%h expected=%h (val=%0d) at %0t",
                 Out, exp_to_bcd(exp_val), exp_val, $time);
    end
endtask

initial begin $dumpfile("Counter_tb.vcd");
$dumpvars(0, Counter_tb); end

initial begin
    Dec     = 0;
    Set     = 0;
    SetZero = 0;
    In      = 0;
    Rst_n   = 0;

    #2000  Rst_n = 1;
    @(posedge Clk);

`ifdef DEKATRON_RANDOM_INIT
    // Разряды стоят где попало: известное состояние даёт только сброс
    $display("Power-on: random positions Out=%h IpOut=%h", Out, IpOut);
    $display("Power-on hard reset test");
    do_rst(1'b1, 1'b0);
    check_out(0);
    check_ip(20'h99900);
    $display("Power-on soft reset test");
    do_rst(1'b0, 1'b0);
    check_out(0);
    check_ip(20'h00000);
`else
    // Счётчик декатронов после включения — в нуле.
    check_out(0);
    check_ip(20'h00000);
`endif

    $display("Increment test (0..%0d)", TOP);
    for (int i=0; i <= TOP; i++) begin
        if (i != 0) do_op(1'b0);
        check_out(i);
    end

    $display("Decrement test (%0d..0)", TOP);
    for (int i=TOP; i >= 0; i--) begin
        if (i != TOP) do_op(1'b1);
        check_out(i);
    end

    $display("Top-limit wrap test");
    do_op(1'b0);                 // 0..255 -> 255
    repeat (255-1) do_op(1'b0);
    check_out(TOP);
    repeat (2) @(posedge Clk);   // at_top регистровый
    do_op(1'b0);                 // 255 + 1 -> 0
    check_out(0);
    repeat (2) @(posedge Clk);
    do_op(1'b1);                 // 0 - 1 -> 255
    check_out(TOP);

    $display("Set value test");
    do_op_full(1'b0, 1'b1, 1'b0, exp_to_bcd(42));
    check_out(42);

    $display("Set zero test");
    do_op_full(1'b0, 1'b0, 1'b1, {WIDTH{1'b0}});
    check_out(0);

    $display("Back-to-back test (one operation per clock)");
    back_to_back();

    $display("Soft reset test");
    do_op(1'b0);
    do_op(1'b0);
    do_op(1'b0);
    do_rst(1'b0, 1'b0);
    check_out(0);
    check_ip(20'h00000);
    // zero/at_top — регистровые признаки, обновляются на следующий такт
    // после установления разряда
    repeat (2) @(posedge Clk);
    if (!Zero) begin
        errors++;
        $display("FAIL: zero flag is not set after soft reset");
    end

    $display("Hard reset test");
    do_op(1'b0);
    do_op(1'b0);
    do_rst(1'b1, 1'b0);
    check_out(0);
    check_ip(20'h99900);

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us Counter Test Success!");
    if (errors) $fatal(1, "Counter test failed");
    $finish;
end

reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > 100000)
      $fatal(1, "Timeout");
  end
end

endmodule
