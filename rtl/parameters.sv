`ifndef DPC_PARAMS
   `define DPC_PARAMS
// Период Clk машины, нс — параметр сборки [TRS v0.24]. По умолчанию
// 10 000 (100 кГц). hsClk — временная база моделей декатрона — всегда в
// HSCLK_DIV = 10 раз быстрее Clk, поэтому единица *_HS = период / 10
`ifndef DEKATRON_CLK_NS
`define DEKATRON_CLK_NS 10000
`endif
`ifndef DEKATRON_HS_NS
`define DEKATRON_HS_NS (`DEKATRON_CLK_NS / 10)
`endif
/* verilator lint_off UNUSEDPARAM */
    parameter IP_DEKATRON_NUM = 4'd5;
    parameter LOOP_DEKATRON_NUM = 4'd2;
    parameter AP_DEKATRON_NUM = 4'd5;
    parameter DATA_DEKATRON_NUM = 4'd3;
    parameter DEKATRON_WIDTH = 4;
    parameter INSN_WIDTH = 4;

    parameter DEBUG_ISA = 1'b0;
    parameter BRAINFUCK_ISA = 1'b1;

    // Тактов hsClk на такт Clk: hsClk всегда в 10 раз быстрее Clk
    parameter HSCLK_DIV = 10;
    // Период Clk и hsClk, нс: абсолютное время для тестбенчей и моделей
    // на задержках (OneShot, Impulse, DekatronTubeDelay, RstTimeRelay).
    // Эмулятор на FPGA считает такты hsClk (10 МГц) и от них не зависит
    parameter CLK_PERIOD_NS = `DEKATRON_CLK_NS;
    parameter HSCLK_NS      = CLK_PERIOD_NS / HSCLK_DIV;

/* verilator lint_on UNUSEDPARAM */

`endif
