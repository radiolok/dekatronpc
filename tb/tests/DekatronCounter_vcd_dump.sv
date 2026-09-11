// VCD dump wrapper for the DekatronCounter cocotb test.
//
// The DUT (DekatronCounter) is elaborated as a root module by Icarus together
// with this module (multiple `-s` roots). This initial block writes the full
// waveform of the counter to DekatronCounter.vcd.
module DekatronCounter_vcd_dump();
    initial begin
        $dumpfile("DekatronCounter.vcd");
        $dumpvars(0, DekatronCounter);
    end
endmodule
