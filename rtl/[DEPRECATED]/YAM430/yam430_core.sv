module yam430_core #(
    parameter DATA_WIDTH = 8,
    parameter REG_NUMBER=16,
    parameter SEL_WIDTH=4
) (
    input wire Rst_n,
    input wire Clk,
    input wire [15:0] Opcode,
    input wire AluSaveOldDestIn//Saves old value of selected dest register
);

wire[(DATA_WIDTH*REG_NUMBER)-1:0] RegFileData;
wire[(DATA_WIDTH*REG_NUMBER)-1:0] RegFileQ;
wire[(DATA_WIDTH*REG_NUMBER)-1:0] RegFileQ_n;
wire [REG_NUMBER-1:0] RegFileWr;


yam430_reg_gile #(
    .DATA_WIDTH(DATA_WIDTH),
    .REG_NUMBER(REG_NUMBER)
) Yam430RegFile(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .Data(RegFileData),
    .Wr(RegFileWr),
    .Q(RegFileQ),
    .Q_n(RegFileQ_n)
);

wire [DATA_WIDTH-1 :0] AluSource;

bn_mux_n_1_generate #(
.DATA_WIDTH(DATA_WIDTH), 
.SEL_WIDTH(SEL_WIDTH)
)  muxAluSource
        (  .data(RegFileQ),
            .sel(Opcode[11:8]),//From which we need to do it
            .y(AluSource)
        );


wire [DATA_WIDTH-1 :0] AluDestIn;
bn_mux_n_1_generate #(
.DATA_WIDTH(DATA_WIDTH), 
.SEL_WIDTH(SEL_WIDTH)
)  muxAluDestIn
        (  .data(RegFileQ),
            .sel(Opcode[3:0]),//From which we need to do it
            .y(AluDestIn)
        );

reg [DATA_WIDTH-1:0] AluOldDestIn;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        AluOldDestIn <= {DATA_WIDTH{1'b0}};
    end
    else begin
        if (AluSaveOldDestIn)
            AluOldDestIn <= AluDestIn;
    end
end


wire AluCaryyIn;
wire AluCaryyOut;
wire [SEL_WIDTH-1:0] AluOpcode;
assign AluOpcode = (Opcode[14] | Opcode[15]) ? Opcode[15:12] : 4'b0000;

wire [DATA_WIDTH-1:0] AluDestOut;

yam430_alu #(
    .DATA_WIDTH(DATA_WIDTH),    
    .SEL_WIDTH(SEL_WIDTH)
) YAM430_ALU (
    .Source(AluSource),
    .DestIn(AluOldDestIn),
    .CarryIn(AluCarryIn),
    .CarryOut(AluCarryOut),
    .Opcode(AluOpcode),
    .DestOut(AluDestOut)
);


demux #(
    .DATA_WIDTH(DATA_WIDTH),
    .SEL_WIDTH(SEL_WIDTH)
) outDemux(
    .in(AluDestOut),
    .sel(AluOpcode),
    .out(RegFileData)
);

endmodule