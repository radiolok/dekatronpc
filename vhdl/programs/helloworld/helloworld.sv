module firmware #(
///home/radiolok/dekatronpc/vhdl/programs/helloworld/helloworld.bfk
parameter portSize = 9,
parameter dataSize = 1)(
/* verilator lint_off UNUSEDSIGNAL */
input wire [portSize-1:0] Address,
/* verilator lint_on UNUSEDSIGNAL */
output reg [dataSize-1:0] Data
);
always_comb
/* verilator lint_off WIDTHEXPAND */
  case(Address)
    9'h0: Data = 4'h2; //+ 
    9'h1: Data = 4'h2; //+ 
    9'h2: Data = 4'h2; //+ 
    9'h3: Data = 4'h2; //+ 
    9'h4: Data = 4'h2; //+ 
    9'h5: Data = 4'h2; //+ 
    9'h6: Data = 4'h2; //+ 
    9'h7: Data = 4'h2; //+ 
    9'h8: Data = 4'h2; //+ 
    9'h9: Data = 4'h2; //+ 
    9'h10: Data = 4'h6; //[ 
    9'h11: Data = 4'h4; //> 
    9'h12: Data = 4'h2; //+ 
    9'h13: Data = 4'h2; //+ 
    9'h14: Data = 4'h2; //+ 
    9'h15: Data = 4'h2; //+ 
    9'h16: Data = 4'h2; //+ 
    9'h17: Data = 4'h2; //+ 
    9'h18: Data = 4'h2; //+ 
    9'h19: Data = 4'h4; //> 
    9'h20: Data = 4'h2; //+ 
    9'h21: Data = 4'h2; //+ 
    9'h22: Data = 4'h2; //+ 
    9'h23: Data = 4'h2; //+ 
    9'h24: Data = 4'h2; //+ 
    9'h25: Data = 4'h2; //+ 
    9'h26: Data = 4'h2; //+ 
    9'h27: Data = 4'h2; //+ 
    9'h28: Data = 4'h2; //+ 
    9'h29: Data = 4'h2; //+ 
    9'h30: Data = 4'h4; //> 
    9'h31: Data = 4'h2; //+ 
    9'h32: Data = 4'h2; //+ 
    9'h33: Data = 4'h2; //+ 
    9'h34: Data = 4'h4; //> 
    9'h35: Data = 4'h2; //+ 
    9'h36: Data = 4'h5; //< 
    9'h37: Data = 4'h5; //< 
    9'h38: Data = 4'h5; //< 
    9'h39: Data = 4'h5; //< 
    9'h40: Data = 4'h3; //- 
    9'h41: Data = 4'h7; //] 
    9'h42: Data = 4'h4; //> 
    9'h43: Data = 4'h2; //+ 
    9'h44: Data = 4'h2; //+ 
    9'h45: Data = 4'h8; //. 
    9'h46: Data = 4'h4; //> 
    9'h47: Data = 4'h2; //+ 
    9'h48: Data = 4'h8; //. 
    9'h49: Data = 4'h2; //+ 
    9'h50: Data = 4'h2; //+ 
    9'h51: Data = 4'h2; //+ 
    9'h52: Data = 4'h2; //+ 
    9'h53: Data = 4'h2; //+ 
    9'h54: Data = 4'h2; //+ 
    9'h55: Data = 4'h2; //+ 
    9'h56: Data = 4'h8; //. 
    9'h57: Data = 4'h8; //. 
    9'h58: Data = 4'h2; //+ 
    9'h59: Data = 4'h2; //+ 
    9'h60: Data = 4'h2; //+ 
    9'h61: Data = 4'h8; //. 
    9'h62: Data = 4'h4; //> 
    9'h63: Data = 4'h2; //+ 
    9'h64: Data = 4'h2; //+ 
    9'h65: Data = 4'h8; //. 
    9'h66: Data = 4'h5; //< 
    9'h67: Data = 4'h5; //< 
    9'h68: Data = 4'h2; //+ 
    9'h69: Data = 4'h2; //+ 
    9'h70: Data = 4'h2; //+ 
    9'h71: Data = 4'h2; //+ 
    9'h72: Data = 4'h2; //+ 
    9'h73: Data = 4'h2; //+ 
    9'h74: Data = 4'h2; //+ 
    9'h75: Data = 4'h2; //+ 
    9'h76: Data = 4'h2; //+ 
    9'h77: Data = 4'h2; //+ 
    9'h78: Data = 4'h2; //+ 
    9'h79: Data = 4'h2; //+ 
    9'h80: Data = 4'h2; //+ 
    9'h81: Data = 4'h2; //+ 
    9'h82: Data = 4'h2; //+ 
    9'h83: Data = 4'h8; //. 
    9'h84: Data = 4'h4; //> 
    9'h85: Data = 4'h8; //. 
    9'h86: Data = 4'h2; //+ 
    9'h87: Data = 4'h2; //+ 
    9'h88: Data = 4'h2; //+ 
    9'h89: Data = 4'h8; //. 
    9'h90: Data = 4'h3; //- 
    9'h91: Data = 4'h3; //- 
    9'h92: Data = 4'h3; //- 
    9'h93: Data = 4'h3; //- 
    9'h94: Data = 4'h3; //- 
    9'h95: Data = 4'h3; //- 
    9'h96: Data = 4'h8; //. 
    9'h97: Data = 4'h3; //- 
    9'h98: Data = 4'h3; //- 
    9'h99: Data = 4'h3; //- 
    9'h100: Data = 4'h3; //- 
    9'h101: Data = 4'h3; //- 
    9'h102: Data = 4'h3; //- 
    9'h103: Data = 4'h3; //- 
    9'h104: Data = 4'h3; //- 
    9'h105: Data = 4'h8; //. 
    9'h106: Data = 4'h4; //> 
    9'h107: Data = 4'h2; //+ 
    9'h108: Data = 4'h8; //. 
    9'h109: Data = 4'h4; //> 
    9'h110: Data = 4'h8; //. 
    9'h111: Data = 4'h1; //H 
    default: Data = {dataSize{1'bx}};
  endcase

/* verilator lint_on WIDTHEXPAND */
endmodule
