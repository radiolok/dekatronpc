module RAM(ADDRESS, DATA, CS, WE, OE);

parameter AddressSize=16;
parameter DataSize=8;

input [AddressSize-1:0] ADDRESS;
inout [DataSize-1:0] DATA;
input WE;//if 0 We do write, else read
input OE;//if OE==0 AND WE==1 we do read
input CS;//CS==0 to do operations

reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

assign DATA = (!CS && !OE) ? Mem[ADDRESS] : {DataSize{1'bz}};

always @(WE)
  if (!CS && !WE)
    Mem[ADDRESS] = DATA;

always @(WE or OE)
  if (!WE && !OE)
    $display("Operational error in RamChip: OE and WE both active");

endmodule