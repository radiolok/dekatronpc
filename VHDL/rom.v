module ROM(Address, Data);

parameter AddressSize=16;
parameter DataSize=8;

input [AddressSize-1:0] Address;
output [DataSize-1:0] Data;


reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

assign Data = Mem[Address];

initial
begin
$readmemh("helloworld.bfk", Mem);
end

endmodule

