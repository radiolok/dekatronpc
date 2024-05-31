module bootloader #(
///home/radiolok/dekatronpc/vhdl/programs/bootloader/bootloader.bfk
parameter portSize = 3,
parameter dataSize = 4)(
/* verilator lint_off UNUSEDSIGNAL */
input wire [portSize-1:0] Address,
/* verilator lint_on UNUSEDSIGNAL */
output reg [dataSize-1:0] Data
);
always_comb
/* verilator lint_off WIDTHEXPAND */
  case(Address)
    3'h0: Data = 4'he; //D 
    3'h1: Data = 4'hb; //A 
    3'h2: Data = 4'ha; //0 
    3'h3: Data = 4'h4; //> 
    3'h4: Data = 4'h6; //{ 
    3'h5: Data = 4'ha; //0 
    3'h6: Data = 4'h7; //} 
    default: Data = {dataSize{1'bx}};
  endcase

/* verilator lint_on WIDTHEXPAND */
endmodule
