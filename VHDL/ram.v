module RAM(Address, Data, CS, WE_n, Clk);

parameter AddressSize=16;
parameter DataSize=8;

input wire [AddressSize-1:0] Address;
inout reg [DataSize-1:0] Data;
input WE_n;//if 0 We do write, else read
input Clk;//Sync operation
input CS;//CS==1 to do operations

reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

assign Data = (CS) ? Mem[Address] : {DataSize{1'bz}};

always @(posedge Clk)
  if (CS & !WE_n) Mem[Address] <= Data;

endmodule