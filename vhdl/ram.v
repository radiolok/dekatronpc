module RAM(Address, In, Out, CS, WE_n, Clk, Rst_n);

parameter AddressSize=16;
parameter DataSize=10;

input wire Rst_n;
input wire [AddressSize-1:0] Address;
input wire [DataSize-1:0] In;
output wire [DataSize-1:0] Out;
input WE_n;//if 0 We do write, else read
input Clk;//Sync operation
input CS;//CS==1 to do operations

reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

reg [DataSize-1:0] Data;

assign Out = CS ? Data : {DataSize{1'bz}};

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n) Data <= {DataSize{1'b0}};
    else if (WE_n) Data <= Mem[Address];
      else Mem[Address] <= In;

endmodule