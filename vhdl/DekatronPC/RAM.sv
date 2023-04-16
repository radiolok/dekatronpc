(* keep_hierarchy = "yes" *) module RAM #(
    parameter ROWS = 30000,
    parameter ADDR_WIDTH = $clog2(ROWS),
    parameter DATA_WIDTH = 8
)(
  input wire Rst_n,
  input wire [ADDR_WIDTH-1:0] Address,
  input wire [DATA_WIDTH-1:0] In,
  output wire [DATA_WIDTH-1:0] Out,
  input WE,//if 1 We do write, else read
  input Clk,//Sync operation
  input CS//CS==1 to do operations
);

// synopsys translate_off
reg [DATA_WIDTH-1:0] Mem [0:ROWS-1];

reg [DATA_WIDTH-1:0] Data;

assign Out = CS ? Data : {DATA_WIDTH{1'bz}};

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n) begin 

      integer  i;
      for (i=0; i < ROWS; i++) 
        Mem[i] <= {DATA_WIDTH{1'b0}};
      Data <= {DATA_WIDTH{1'b0}};
    end
    else if (WE) Mem[Address] <= In;
      else Data <= Mem[Address];
// synopsys translate_on

endmodule
