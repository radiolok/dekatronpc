module ROM(Clk, Rst_n, Address, Insn);

parameter AddressSize=16;

input wire Clk;
input wire Rst_n;

input wire [AddressSize-1:0] Address;
output reg[3:0] Insn;

wire [AddressSize-3:0] AddressRom = Address[AddressSize-1:2];

wire [15:0] StorageData;
wire [3:0] ActiveInsn = Address[1] ? 
            (Address[0]? StorageData[15:12] : StorageData[11:8]):
            (Address[0]? StorageData[7:4] : StorageData[3:0]);

helloworld storage(.Address(AddresssRom),
                    .Data(StorageData));


always @(posedge Clk, negedge Rst_n)
    if (~Rst_n)
        Insn <= {4'b0000};
    else
        Insn <= ActiveInsn;

endmodule

