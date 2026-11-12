module bootloader #(
// programs/bootloader.bfk, ISA16 (doc/isa16.md): one decade, 9990..9999.
// After a Hard Reset AP = Data = 0: 0<{0<} clears all data memory (the first
// '<' wraps AP 0 -> 999), then LD on 9999 starts loading (IP wraps to 0)
parameter portSize = 4,
parameter dataSize = 4)(
/* verilator lint_off UNUSEDSIGNAL */
input wire [portSize-1:0] Address,
/* verilator lint_on UNUSEDSIGNAL */
output reg [dataSize-1:0] Data
);

always_comb
/* verilator lint_off WIDTHEXPAND */
  case(Address[3:0])
`ifndef SIMPLEBOOT
    4'h0: Data = 4'ha; //0 [-]
    4'h1: Data = 4'h5; //<
    4'h2: Data = 4'he; //{
    4'h3: Data = 4'ha; //0 [-]
    4'h4: Data = 4'h5; //<
    4'h5: Data = 4'hf; //}
`endif
    4'h9: Data = 4'hb; //S LD
    default: Data = {dataSize{1'b0}};
  endcase
/* verilator lint_on WIDTHEXPAND */

endmodule
