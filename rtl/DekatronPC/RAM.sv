(* keep_hierarchy = "yes" *) module RAM #(
    parameter ROWS = 30000,
    parameter ADDR_WIDTH = $clog2(ROWS),
    parameter DATA_WIDTH = 8
)(
  input wire Rst_n,
  input Clk,//Sync operation
  input wire [ADDR_WIDTH-1:0] Address,//BCD
  input wire [DATA_WIDTH-1:0] In,
  output wire [DATA_WIDTH-1:0] Out,
`ifdef EMULATOR
  input wire [ADDR_WIDTH-1:0] Address1,
  output wire [DATA_WIDTH-1:0] Out1,
`endif
  input WE,//if 1 We do write, else read
  input CS//CS==1 to do all operations
);

`ifndef SYNTH
    //As RAM would not be evaluated with vacuum tubes
    reg [DATA_WIDTH-1:0] Mem [0:ROWS-1];

    reg [DATA_WIDTH-1:0] Data;

    assign Out = CS ? Data : {DATA_WIDTH{1'bz}};

    always @(posedge Clk, negedge Rst_n) begin
        if (~Rst_n) begin
    //TODO:  Bootloader should cleanUp Memory itself
	 //synopsys translate_off
    /* verilator lint_off BLKSEQ */
          integer  i;
          for (i=0; i < ROWS; i++) 
            Mem[i] = {DATA_WIDTH{1'b0}};
    /* verilator lint_off BLKSEQ */
			Data <= {DATA_WIDTH{1'b0}};
			//synopsys translate_on
        end
        else if (WE) Mem[Address] <= In;
          else Data <= Mem[Address];
    end


    `ifdef EMULATOR
      reg [DATA_WIDTH-1:0] Data1;

      assign Out1 = CS ? Data1 : {DATA_WIDTH{1'bz}};

      always @(negedge Clk, negedge Rst_n) begin
          if (~Rst_n) begin
            Data1 <= {DATA_WIDTH{1'b0}};
          end
          else Data1 <= Mem[Address1];
      end
    `endif

`endif
endmodule
