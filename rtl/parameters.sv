`ifndef DPC_PARAMS
   `define DPC_PARAMS
// Период Clk машины, нс — параметр сборки [TRS v0.24]. По умолчанию
// 10 000 (100 кГц). hsClk — временная база моделей декатрона — всегда в
// HSCLK_DIV = 10 раз быстрее Clk, поэтому единица *_HS = период / 10
`ifndef DEKATRON_CLK_NS
`define DEKATRON_CLK_NS 10000
`endif

// Модель на задержках (`DEKATRON_DELAY_MODEL): синтез и нетлист ламповой
// машины. hsClk в ней нет вовсе — он только для тактовой модели декатрона
// на FPGA и в симуляции без задержек. Длительности — в нс, как у RC-цепей
// и самого декатрона [TRS v0.25]:
//   GUIDE_STEP / FALL_STEP — переход на подкатод и сваливание (оценки;
//     FALL_STEP 1000 по SPICE-модели А110, doc/dekatron_physics.md [TRS v0.31])
//   WRITE_MIN              — запись по катоду, она же сброс (оценка, OPEN-013;
//     с TRS v0.56 запись и сброс — одно событие, RESET_MIN убран)
//   GUIDE_MAX              — предел импульса подкатода (только диагностика)
//   PHASE_DELAY / PHASE1 / PHASE2 — нарезка такта генератором фаз
//     (REQ-PULSE-009); ламповую сборку задают synth_sim.sh -o/-w
//   EDGE                   — импульс дифференцирующей цепи (Impulse)
`ifndef DEKATRON_GUIDE_STEP_NS
`define DEKATRON_GUIDE_STEP_NS 200
`endif
`ifndef DEKATRON_FALL_STEP_NS
`define DEKATRON_FALL_STEP_NS 1000
`endif
`ifndef DEKATRON_GUIDE_MAX_NS
`define DEKATRON_GUIDE_MAX_NS 10000
`endif
`ifndef DEKATRON_WRITE_MIN_NS
`define DEKATRON_WRITE_MIN_NS 5000
`endif
`ifndef DEKATRON_PHASE_DELAY_NS
`define DEKATRON_PHASE_DELAY_NS 2500  // DFFP_J2N16 разрешений декад снимает D в конце окна: 0 даёт гонку с dec (TRS v0.60)
`endif
`ifndef DEKATRON_PHASE1_NS
`define DEKATRON_PHASE1_NS 1000      // [TRS v0.59] было 3000: импульс подкатода 1 мкс (владелец)
`endif
`ifndef DEKATRON_PHASE2_NS
`define DEKATRON_PHASE2_NS 1000      // [TRS v0.59] было 3000
`endif
`ifndef DEKATRON_EDGE_NS
`define DEKATRON_EDGE_NS 100
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
    // Период Clk и hsClk, нс: тактовая база тестбенчей. Модель на
    // задержках hsClk не знает (длительности — макросы *_NS выше)
    parameter CLK_PERIOD_NS = `DEKATRON_CLK_NS;
    parameter HSCLK_NS      = CLK_PERIOD_NS / HSCLK_DIV;

/* verilator lint_on UNUSEDPARAM */

`endif
