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
  output reg rdy_o,
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
    reg [ADDR_WIDTH-1:0] AddressClean;

    assign Out = CS ? Data : {DATA_WIDTH{1'bz}};

    always @(posedge Clk, negedge Rst_n) begin
        if (~Rst_n) begin
            rdy_o <= 1'b0;
            AddressClean <= ROWS - 1;
        end
        else begin 
          if (rdy_o) begin  
            if (WE) Mem[Address] <= In;
            else Data <= Mem[Address];
          end else begin
            AddressClean <= AddressClean -1;
            Mem[AddressClean] <= '0;
            if (AddressClean == 0) begin
              rdy_o <= 1;
            end
          end
        end
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
