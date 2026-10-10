`ifdef VCD_DUMP
module vcd_dump_wrapper();
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule
`endif
