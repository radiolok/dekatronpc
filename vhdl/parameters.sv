`ifndef DPC_PARAMS
   `define DPC_PARAMS
/* verilator lint_off UNUSEDPARAM */ 
    parameter IP_DEKATRON_NUM = 4'd6;
    parameter LOOP_DEKATRON_NUM = 4'd3;
    parameter AP_DEKATRON_NUM = 4'd5;
    parameter DATA_DEKATRON_NUM = 4'd3;
    parameter DEKATRON_WIDTH = 4;
    parameter INSN_WIDTH = 4;

    parameter DEBUG_ISA = 1'b0;
    parameter BRAINFUCK_ISA = 1'b1;

/* verilator lint_on UNUSEDPARAM */

`endif
