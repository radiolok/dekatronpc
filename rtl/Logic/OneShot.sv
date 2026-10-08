/* verilator lint_off DECLFILENAME */
// Одновибратор: окно длительностью DELAY тактов Clk от фронта En
// (IMP_ON_EN = 1: En сам входит в выход). Повторный En внутри окна его
// не продлевает; если En держится до конца окна, окно начинается снова.
//
// `DEKATRON_DELAY_MODEL: модель без тактовой базы. Clk не используется,
// окно — DELAY * HS_NS нс от фронта En (HS_NS = период hsClk 10 МГц,
// который заменяет модель). Иголки нулевой длительности на En (дельта-
// циклы нетлиста) окно не запускают: в тактовой модели их не видит
// фронт Clk, здесь их отсекает инерционная задержка 1 пс. Только для
// Icarus; в нетлисте OneShot — чёрный ящик.
module OneShot #(
    parameter DELAY=1'b1,
    parameter WIDTH=$clog2(DELAY),
    parameter IMP_ON_EN = 1'b1,
    parameter HS_NS = 100   // такт Clk в модели на задержках, нс
)(
/* verilator lint_off UNUSEDSIGNAL */
    input Clk,
/* verilator lint_on UNUSEDSIGNAL */
    input En,
    input Rst_n,
    output wire Impulse
);
`ifndef SYNTH
`ifdef DEKATRON_DELAY_MODEL
timeunit 1ns;
timeprecision 1ps;

wire en_f;
assign #0.001 en_f = En & Rst_n;

reg win = 1'b0;

always @(posedge en_f) begin : shot
    while (en_f) begin
        win = 1'b1;
        #(DELAY * HS_NS);
        win = 1'b0;
    end
end

always @(negedge Rst_n) begin
    disable shot;
    win = 1'b0;
end

generate
    if (IMP_ON_EN) begin : gen_imp_on_en_en
        assign Impulse = win | En;
    end
    else begin : gen_imp_on_en_dis
        assign Impulse = win;
    end
endgenerate
`else
localparam DELAY_COMP=DELAY-1;
reg [WIDTH:0] count;

generate
    if (IMP_ON_EN) begin : gen_imp_on_en_en
        assign Impulse = (|count) | En;
    end
    else begin : gen_imp_on_en_dis
        assign Impulse = (|count);
    end
endgenerate

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        count <= 0;
    end
    else begin
        if (En | Impulse) begin
            count <= count + 1'b1;
            if (count == (WIDTH+1)'(DELAY_COMP)) begin
                count <= 0;
            end
        end
    end
end
`endif
`endif
endmodule

module OneShot_tb();

reg Clk = 1'b0;
reg Rst_n = 1'b0;
reg En;
wire Impulse;

//synopsys translate_off

initial begin $dumpfile("OneShot_tb.vcd");
$dumpvars(0,OneShot_tb); end

OneShot #(.DELAY(10)
)oneshot(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .En(En),
    .Impulse(Impulse)
);

initial begin
    Clk <= 1'b0;
    forever #1 Clk = ~Clk;
end

initial
begin
	#3
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");

	#400;
	$display($time, "<< Simulation Complete >>");
	$finish;
end

always @(posedge Clk) begin
    if (~Impulse)
        En <= 1'b1;
    else
        En <= 1'b0;
end
//synopsys translate_on
endmodule
/* verilator lint_on DECLFILENAME */
