module looptest #(
  parameter portSize = 8,
  parameter dataSize = 4
)(Address, Data);


/* verilator lint_off UNUSEDSIGNAL */
input logic [portSize-1:0] Address;
/* verilator lint_on UNUSEDSIGNAL */
output logic [dataSize-1:0] Data;

always_comb
  case(Address[7:0])
    8'b0000: Data = {4'b0010}; //+
    8'b0001: Data = {4'b0010}; //+
    8'b0010: Data = {4'b0010}; //+
    8'b0011: Data = {4'b0010}; //+
    8'b0100: Data = {4'b0010}; //+
    8'b0101: Data = {4'b0010}; //+
    8'b0110: Data = {4'b0010}; //+
    8'b0111: Data = {4'b0010}; //+
    8'b1000: Data = {4'b0010}; //+
    8'b1001: Data = {4'b0110}; //[
    8'b1010: Data = {4'b0011}; //-
    8'b1011: Data = {4'b0010}; //+
    8'b1100: Data = {4'b0011}; //-
    8'b1101: Data = {4'b0010}; //+
    8'b1110: Data = {4'b0011}; //-
    8'b1111: Data = {4'b0111}; //]
    8'b00010000: Data = {4'b0001}; //H
    8'b00010001: Data = {4'b0000}; // 
    default: Data = {dataSize{1'b0}};
  endcase

endmodule
