module bootloader #(
///mnt/d/radiolok@oc.urlnn.ru/Projects/20180271-DekatronPC/vhdl/programs/bootloader/bootloader.bfk
parameter portSize = 8,
parameter dataSize = 4)(
/* verilator lint_off UNUSEDSIGNAL */
input wire [portSize-1:0] Address,
/* verilator lint_on UNUSEDSIGNAL */
output reg [dataSize-1:0] Data
);
always_comb
/* verilator lint_off WIDTHEXPAND */
  case(Address)
    8'h00: Data = 4'he; //D 
    8'h01: Data = 4'hb; //A 
    8'h02: Data = 4'ha; //0
    8'h03: Data = 4'hF; //B
    8'h04: Data = 4'h5; //< 
    8'h05: Data = 4'he; //D 
    8'h06: Data = 4'h6; //{ 
    8'h07: Data = 4'ha; //0 
    8'h08: Data = 4'hF; //B
    8'h09: Data = 4'h5; //< 
    8'h10: Data = 4'he; //D 
    8'h11: Data = 4'h7; //}
    8'h12: Data = 4'hF; //B 
    default: Data = {dataSize{1'b0}};
  endcase

/* verilator lint_on WIDTHEXPAND */
endmodule
