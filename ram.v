module RAM(Address, Data, CS, WE, OE);

parameter AddressSize=16;
parameter DataSize=8;

input [AddressSize-1:0] Address;
inout [DataSize-1:0] Data;
input WE;//if 0 We do write, else read
input OE;//if OE==0 AND WE==1 we do read
input CS;

reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

assign Data = (!CS && !OE) ? Mem[Address] : {DataSize{1'bz}};

always @(WE)
  if (!CS && !WE)
    Mem[Address] = Data;

always @(WE or OE)
  if (!WE && !OE)
    $display("Operational error in RamChip: OE and WE both active");

endmodule