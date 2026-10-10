`timescale 1ns/1ps

//----------------------------------------------------------------------
// Dekatron_tb — тест декатронного модуля
//
// Интерфейс DUT обновлён под v0.7:
//   старая связка Dekatron + DekatronPulseSender(Pulses) + BinToBcd
//   заменена на DekatronModule (DekatronTubeV2 + DekatronPulseSender +
//   DekatronPhaseGen + BcdToBinEn + BinToBcd).
//
// С T5 (doc/tube_count_reduction.md §17) формирователь импульсов стоит
// в счётчике, а модуль получает общие шины GuideA/GuideB и разрешение En.
// Тест ставит у себя DekatronPulseSender со своим генератором фаз
// (EXT_PHASES = 0), как это делал модуль прежде, и держит En = 1.
//
// Шаг задаётся уровнем StepF/StepR на весь такт Clk; показание Out
// достоверно по окончании такта шага. Признака Valid у модуля нет:
// длительности известны заранее. Запись/сброс удерживаются заметно
// дольше WRITE_MIN_HS / RESET_MIN_HS тактов hsClk.
//----------------------------------------------------------------------
module Dekatron_tb();

parameter WIDTH    = 4;
parameter TOP_TEST = 12;

reg hsClk;
reg Clk;
reg Rst_n;

`ifdef DEKATRON_DELAY_MODEL
// Период Clk в нс (synth_sim.sh -c): поиск частоты, на которой работает
// нетлист с задержками ламп (doc/vtube_sdf_timing.md)
`ifndef CLK_NS
`define CLK_NS 1000
`endif
// Модель на задержках: hsClk не нужен и стоит в нуле — так проверяется,
// что DUT от него не зависит. Clk 1 МГц с той же фазой, что дал бы
// делитель: первый фронт через 50 нс после снятия Rst_n.
initial hsClk = 1'b0;
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
    forever #50 hsClk = ~hsClk;
end

ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
    .clock_in(hsClk),
    .clock_out(Clk)
);
`endif

reg             StepF    = 1'b0;
reg             StepR    = 1'b0;
reg             SetData  = 1'b0;
reg             SetZero  = 1'b0;
reg             SetTop   = 1'b0;
reg [WIDTH-1:0] In       = '0;

wire [WIDTH-1:0] Out;
wire             Zero;
wire             Nine;
wire             TopPin;

wire GuideA;
wire GuideB;

// Формирователь импульсов счётчика: в DekatronCounter он один на все декады
DekatronPulseSender #(
    .EXT_PHASES (1'b0)
) pulseSender (
`ifdef DEKATRON_DELAY_MODEL
    .hsClk   (1'b0),
`else
    .hsClk   (hsClk),
`endif
    .Clk     (Clk),
    .Rst_n   (Rst_n),
    .StepF   (StepF),
    .StepR   (StepR),
    .Phase1_i(1'b0),
    .Phase2_i(1'b0),
    .GuideA  (GuideA),
    .GuideB  (GuideB)
);

DekatronModule #(
    .READ           (1'b1),
    .WRITE          (1'b1),
    .TOP_LIMIT_MODE (1'b1),
    .TOP_PIN_OUT    (4'd9),
    .INIT_DIGIT     (4'd0)
) dek (
    .hsClk   (hsClk),
    .GuideA  (GuideA),
    .GuideB  (GuideB),
    .En      (1'b1),
    .In      (In),
    .SetData (SetData),
    .SetZero (SetZero),
    .SetTop  (SetTop),
    .Out     (Out),
    .Zero    (Zero),
    .Nine    (Nine),
    .TopPin  (TopPin)
);

initial begin $dumpfile("dekatron_tb.vcd");
$dumpvars(0, Dekatron_tb); end

//----------------------------------------------------------------------
// Один шаг: уровень StepF/StepR на весь такт Clk
//----------------------------------------------------------------------
task automatic step(input bit down);
    @(posedge Clk);
    StepF <= ~down;
    StepR <=  down;
    @(posedge Clk);
    StepF <= 1'b0;
    StepR <= 1'b0;
    @(negedge Clk);
endtask

task automatic write_value(input [WIDTH-1:0] v);
    @(posedge Clk);
    In      <= v;
    SetData <= 1'b1;
    repeat (15) @(posedge Clk);     // 150 hs > WRITE_MIN_HS = 100
    SetData <= 1'b0;
    In      <= '0;
    @(negedge Clk);
endtask

task automatic set_position(input bit top, input bit zero);
    @(posedge Clk);
    SetTop  <= top;
    SetZero <= zero;
    repeat (15) @(posedge Clk);     // 150 hs > RESET_MIN_HS = 100
    SetTop  <= 1'b0;
    SetZero <= 1'b0;
    @(negedge Clk);
endtask

int errors = 0;

task automatic check_out(input [WIDTH-1:0] expected);
    if (Out !== expected) begin
        errors++;
        $display("FAIL: Out=%0d expected=%0d at %0t", Out, expected, $time);
    end
endtask

initial begin
    Rst_n   <= 1'b0;
    StepF   <= 1'b0;
    StepR   <= 1'b0;
    SetData <= 1'b0;
    SetZero <= 1'b0;
    SetTop  <= 1'b0;
    In      <= '0;

    #2000 Rst_n <= 1'b1;
    check_out(0);

    $display("Count forward");
    for (int i = 1; i <= TOP_TEST; i++) begin
        step(1'b0);
        check_out(i % 10);
    end

    $display("Count reverse");
    for (int i = TOP_TEST; i >= 1; i--) begin
        step(1'b1);
        check_out((i - 1) % 10);
    end
    check_out(0);

    $display("Write value");
    write_value(4'd7);
    check_out(4'd7);

    $display("Write value 0..9");
    for (int i = 0; i <= 9; i++) begin
        write_value(4'(i));
        check_out(4'(i));
    end

    $display("Reset to zero");
    set_position(1'b0, 1'b1);
    check_out(0);
    if (!Zero) begin
        errors++;
        $display("FAIL: zero position not flagged after reset0");
    end

    $display("Reset to nine");
    set_position(1'b1, 1'b0);
    check_out(9);
    if (!Nine) begin
        errors++;
        $display("FAIL: nine position not flagged after resetN");
    end

    if (errors)
        $display($time/1000, "us << Simulation Complete >> errors=%0d", errors);
    else
        $display($time/1000, "us Dekatron Test Success!");
    if (errors) $fatal(1, "Dekatron test failed");
    $finish;
end

reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end else begin
    CLOCK_TICK <= CLOCK_TICK + 1;
    if (CLOCK_TICK > 20000)
      $fatal(1, "Timeout");
  end
end

endmodule
