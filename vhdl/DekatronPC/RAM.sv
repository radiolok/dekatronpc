module RAM #(
    parameter DEKATRON_NUM = 6,
    parameter DEKATRON_WIDTH = 3,
    parameter DATA_WIDTH = 4
)(
  input wire Rst_n,
  input wire [DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,
  input wire [DATA_WIDTH-1:0] In,
  output wire [DATA_WIDTH-1:0] Out,
  input WE_n,//if 0 We do write, else read
  input Clk,//Sync operation
  input CS//CS==1 to do operations
);

reg [DATA_WIDTH-1:0] Mem [0:(1<<DEKATRON_NUM*DEKATRON_WIDTH)-1];

reg [DATA_WIDTH-1:0] Data;

assign Out = CS ? Data : {DATA_WIDTH{1'bz}};

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n) Data <= {DATA_WIDTH{1'b0}};
    else if (WE_n) Data <= Mem[Address];
      else Mem[Address] <= In;

endmodule