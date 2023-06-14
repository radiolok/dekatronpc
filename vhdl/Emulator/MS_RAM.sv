module MS_RAM #(
    parameter ROWS = 12'h100,
    parameter ADDR_WIDTH = $clog2(ROWS),
    parameter DATA_WIDTH = 8
)(
  input wire Rst_n,
  input Clk,//Sync operation
  input wire [ADDR_WIDTH-1:0] Address,
  input wire [DATA_WIDTH-1:0] In,
  output wire [DATA_WIDTH-1:0] Out,

  input WE,//if 1 We do write, else read
  input CS//CS==1 to do all operations
);

// synopsys translate_off
//As RAM would not be evaluated with vacuum tubes
reg [DATA_WIDTH-1:0] Mem [0:ROWS-1];

reg [DATA_WIDTH-1:0] Data;

assign Out = CS ? Data : {DATA_WIDTH{1'bz}};

always @(negedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
//TODO:  Bootloader should cleanUp Memory itself
/* verilator lint_off BLKSEQ */
      integer  i;
      for (i=0; i < ROWS; i++) 
        Mem[i] = {DATA_WIDTH{1'b0}};
      Data <= {DATA_WIDTH{1'b0}};
/* verilator lint_off BLKSEQ */
    end
    else if (WE) Mem[Address] <= In;
      else Data <= Mem[Address];
end

// synopsys translate_on
endmodule
