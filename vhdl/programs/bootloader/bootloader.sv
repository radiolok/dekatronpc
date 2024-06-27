module bootloader #(
///mnt/d/radiolok@oc.urlnn.ru/Projects/20180271-DekatronPC/vhdl/programs/bootloader/bootloader.bfk
parameter portSize = 4,
parameter dataSize = 4)(
/* verilator lint_off UNUSEDSIGNAL */
input wire [portSize-1:0] Address,
/* verilator lint_on UNUSEDSIGNAL */
output reg [dataSize-1:0] Data
);
always_comb
/* verilator lint_off WIDTHEXPAND */
  case(Address)
    4'h0: Data = 4'he; //D 
    4'h1: Data = 4'hb; //A 
    4'h2: Data = 4'ha; //0 
    4'h3: Data = 4'h5; //< 
    4'h4: Data = 4'h6; //{ 
    4'h5: Data = 4'h5; //< 
    4'h6: Data = 4'ha; //0 
    4'h7: Data = 4'h7; //} 
    default: Data = {dataSize{1'bx}};
  endcase

/* verilator lint_on WIDTHEXPAND */
endmodule
