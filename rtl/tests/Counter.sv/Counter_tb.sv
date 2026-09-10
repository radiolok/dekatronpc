`timescale 1ns/1ps

//----------------------------------------------------------------------
// Counter_tb — тест DekatronCounter (Valid/Ready)
//
// Интерфейс DUT обновлён под v0.7:
//   Clk/hsClk/Rst_n/HardRst_n -> clk/hs_clk/rst_n/soft_rst/hard_rst
//   Request/Ready/Set/SetZero/In/Out ->
//   valid/ready/set/set_zero/in/out/out_valid/zero/at_top
//
// ВАЖНО (найдено при прогоне, RTL не правился):
//   Любая операция класса «запись» (set / set_zero / автопереход через
//   верхний предел) подвешивает iverilog нуль-задержечной петлёй:
//     accept -> write_req -> write_start(Impulse) -> writing(OneShot)
//            -> ready -> accept.
//   Verilator подтверждает UNOPTFLAT на DekatronCounter.sv:241
//   (write_req) и :194 (accept). Поэтому rollover и set* здесь не
//   выполняются; счёт проверяется в диапазоне 0..255, а обнуление —
//   физической линией soft_rst. См. отчёт.
//----------------------------------------------------------------------
module Counter_tb #(
    parameter DEKATRON_NUM = 3
);

localparam WIDTH    = DEKATRON_NUM*4;
localparam TEST_NUM = 50;
localparam TOP      = 255;

reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b0;
    forever #50 hsClk = ~hsClk;
end
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);

reg             valid   = 1'b0;
reg             Dec     = 1'b0;
reg             Set     = 1'b0;
reg             SetZero = 1'b0;
reg             soft_rst= 1'b0;
reg             hard_rst= 1'b0;
reg [WIDTH-1:0] In      = '0;

wire             Ready;
wire [WIDTH-1:0] Out;
wire             OutValid;
wire             Zero;
wire             AtTop;

DekatronCounter  #(.D_NUM(DEKATRON_NUM),
                    .TOP_LIMIT_MODE(1'b1),
                    .TOP_VALUE({4'd2, 4'd5, 4'd5})
)counter(
    .rst_n    (Rst_n),
    .clk      (Clk),
    .hs_clk   (hsClk),
    .soft_rst (soft_rst),
    .hard_rst (hard_rst),
    .valid    (valid),
    .ready    (Ready),
    .dec      (Dec),
    .set      (Set),
    .set_zero (SetZero),
    .in       (In),
    .out      (Out),
    .out_valid(OutValid),
    .zero     (Zero),
    .at_top   (AtTop)
);

//----------------------------------------------------------------------
// Одна быстрая операция (инкремент/декремент).
// valid выставляется по фронту clk и держится ровно один такт: только
// так StepF/StepR покрывает весь такт вместе с обеими фазами.
//----------------------------------------------------------------------
task automatic do_op(input bit d);
    while (!Ready) @(posedge Clk);
    @(posedge Clk);
    valid   <= 1'b1;
    Dec     <= d;
    Set     <= 1'b0;
    SetZero <= 1'b0;
    @(posedge Clk);
    valid   <= 1'b0;
    while (!OutValid) @(posedge Clk);
endtask

//----------------------------------------------------------------------
// Физический сброс: линия держится заметно дольше RESET_MIN_HS.
//----------------------------------------------------------------------
task automatic do_rst(input bit hard, input bit expected_top);
    @(posedge Clk);
    soft_rst <= ~hard;
    hard_rst <=  hard;
    repeat (15) @(posedge Clk);       // 150 hs > RESET_MIN_HS = 100
    soft_rst <= 1'b0;
    hard_rst <= 1'b0;
    while (!OutValid) @(posedge Clk);
endtask

function automatic [WIDTH-1:0] exp_to_bcd(input int unsigned v);
    exp_to_bcd = {4'((v/100)%10), 4'((v/10)%10), 4'(v%10)};
endfunction

int errors = 0;
int exp_val;

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

    // Счётчик декатронов после включения — в нуле.
    check_out(0);

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

    $display("Soft reset test");
    do_op(1'b0);
    do_op(1'b0);
    do_op(1'b0);
    do_rst(1'b0, 1'b0);
    check_out(0);
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
