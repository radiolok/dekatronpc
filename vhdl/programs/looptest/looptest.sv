module loopTest(Address, Data);

parameter portSize = 8;
parameter dataSize = 4;

input logic [portSize-1:0] Address;
output logic [dataSize-1:0] Data;

always_comb
  case(Address)
    8'b0000: Data = {4'b0001}; //+
    8'b0001: Data = {4'b0001}; //+
    8'b0010: Data = {4'b0001}; //+
    8'b0011: Data = {4'b0100}; //[
    8'b0100: Data = {4'b0001}; //+
    8'b0101: Data = {4'b0001}; //+
    8'b0110: Data = {4'b0001}; //+
    8'b0111: Data = {4'b0100}; //[
    8'b1000: Data = {4'b0001}; //+
    8'b1001: Data = {4'b0001}; //+
    8'b1010: Data = {4'b0001}; //+
    8'b1011: Data = {4'b0101}; //]
    8'b1100: Data = {4'b0001}; //+
    8'b1101: Data = {4'b0001}; //+
    8'b1110: Data = {4'b0001}; //+
    8'b1111: Data = {4'b0101}; //]
    8'b10000: Data = {4'b0001}; //+
    8'b10001: Data = {4'b0001}; //+
    8'b10010: Data = {4'b0001}; //+
    8'b10011: Data = {4'b0000}; // 
    default: Data = {dataSize{1'b0}};
  endcase

endmodule
