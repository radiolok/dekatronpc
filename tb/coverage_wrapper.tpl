`timescale 1ns/1ps
module cocotb_iverilog_dump();
    __TOPLEVEL__ cmp();
initial begin
    $dumpfile("sim_build/dbg.vcd");
    $dumpvars(0, cmp);
end
endmodule
