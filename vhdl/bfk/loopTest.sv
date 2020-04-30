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
    8'b0011: Data = {4'b0101}; //[
    8'b0100: Data = {4'b0001}; //+
    8'b0101: Data = {4'b0001}; //+
    8'b0110: Data = {4'b0001}; //+
    8'b0111: Data = {4'b0101}; //[
    8'b1000: Data = {4'b0001}; //+
    8'b1001: Data = {4'b0001}; //+
    8'b00010000: Data = {4'b0001}; //+
    8'b00010001: Data = {4'b0110}; //]
    8'b00010010: Data = {4'b0001}; //+
    8'b00010011: Data = {4'b0001}; //+
    8'b00010100: Data = {4'b0001}; //+
    8'b00010101: Data = {4'b0110}; //]
    8'b00010110: Data = {4'b0001}; //+
    8'b00010111: Data = {4'b0001}; //+
    8'b00011000: Data = {4'b0001}; //+
    8'b00011001: Data = {4'b0000}; // 
    default: Data = {dataSize{1'b0}};
  endcase

endmodule
