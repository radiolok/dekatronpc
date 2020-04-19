module RAM(ADDRESS, DATA, CS, WE_n, Clk);

parameter AddressSize=16;
parameter DataSize=8;

input wire [AddressSize-1:0] ADDRESS;
inout reg [DataSize-1:0] DATA;
input WE_n;//if 0 We do write, else read
input Clk;//Sync operation
input CS;//CS==1 to do operations

reg [DataSize-1:0] Mem [0:(1<<AddressSize)-1];

always @(posedge Clk)
  if (CS) begin
    if (WE_n)
      Mem[ADDRESS] <= DATA;
    else
      DATA <= Mem[ADDRESS];
  end
  else
    DATA <= {DataSize{1'bz}};

endmodule