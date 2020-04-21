module helloworld(Address, Data);

parameter portSize = 10;
parameter dataSize = 16;

input logic [portSize-1:0] Address;
output logic [dataSize-1:0] Data;

always_comb
  case(Address)
    10'b00: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b01: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b10: Data = {4'b0011, 4'b0101, 4'b0001, 4'b0001};
    10'b000100: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b000101: Data = {4'b0011, 4'b0001, 4'b0001, 4'b0001};
    10'b001000: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b001001: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b001010: Data = {4'b0001, 4'b0011, 4'b0001, 4'b0001};
    10'b001100: Data = {4'b0001, 4'b0011, 4'b0001, 4'b0001};
    10'b001101: Data = {4'b0100, 4'b0100, 4'b0100, 4'b0100};
    10'b010000: Data = {4'b0001, 4'b0011, 4'b0110, 4'b0010};
    10'b010001: Data = {4'b0001, 4'b0011, 4'b0111, 4'b0001};
    10'b010010: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0111};
    10'b010100: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b010101: Data = {4'b0001, 4'b0001, 4'b0111, 4'b0111};
    10'b011000: Data = {4'b0001, 4'b0011, 4'b0111, 4'b0001};
    10'b011001: Data = {4'b0100, 4'b0100, 4'b0111, 4'b0001};
    10'b011010: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b011100: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b011101: Data = {4'b0001, 4'b0001, 4'b0001, 4'b0001};
    10'b100000: Data = {4'b0111, 4'b0001, 4'b0001, 4'b0001};
    10'b100001: Data = {4'b0001, 4'b0001, 4'b0111, 4'b0011};
    10'b100010: Data = {4'b0010, 4'b0010, 4'b0111, 4'b0001};
    10'b100100: Data = {4'b0010, 4'b0010, 4'b0010, 4'b0010};
    10'b100101: Data = {4'b0010, 4'b0010, 4'b0010, 4'b0111};
    10'b0001000000: Data = {4'b0010, 4'b0010, 4'b0010, 4'b0010};
    10'b0001000001: Data = {4'b0001, 4'b0011, 4'b0111, 4'b0010};
    10'b0001000010: Data = {4'b0000, 4'b0111, 4'b0011, 4'b0111};
    default: Data = {dataSize{1'b0}};
  endcase

endmodule
