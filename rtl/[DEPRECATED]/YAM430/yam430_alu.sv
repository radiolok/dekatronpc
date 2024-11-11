module FullAdder #(
    parameter DATA_WIDTH=8
)(
    input wire [DATA_WIDTH-1 :0] SourceA,
    input wire [DATA_WIDTH-1 :0] SourceB,
    input wire CarryIn,
    input wire one,//1 if subcstruction
    output wire CarryOut,
    output wire [DATA_WIDTH-1 :0] Dest
);

wire [DATA_WIDTH:0] SourceAInt;
wire [DATA_WIDTH:0] SourceBInt;
wire [DATA_WIDTH:0] DestInt;

assign SourceAInt = {1'b0, SourceA};
assign SourceBInt = {1'b0, SourceB};


assign DestInt = SourceAInt + SourceBInt + CarryIn + one; 
assign Dest = DestInt[DATA_WIDTH-1 :0];
assign CarryOut = DestInt[DATA_WIDTH];

endmodule//FullAdder

parameter MOV = 4'b0100;
parameter ADD = 4'b0101;
parameter ADDC = 4'b0110;
parameter SUBC = 4'b0111;
parameter SUB = 4'b1000;
parameter CMP = 4'b1001;
parameter DADD = 4'b1010;//NOT SUPPORTED
parameter BIT = 4'b1011;
parameter BIC = 4'b1100;
parameter BIS = 4'b1101;
parameter XOR = 4'b1110;
parameter AND = 4'b1111;

module yam430_xor #(
    parameter DATA_WIDTH=8
)(
    input wire [DATA_WIDTH-1 :0] SourceA,
    input wire [DATA_WIDTH-1 :0] SourceB,
    output wire [DATA_WIDTH-1 :0] Dest
);

assign Dest = SourceA ^ SourceB;

endmodule

module yam430_and #(
    parameter DATA_WIDTH=8
)(
    input wire [DATA_WIDTH-1 :0] SourceA,
    input wire [DATA_WIDTH-1 :0] SourceB,
    output wire [DATA_WIDTH-1 :0] Dest
);

assign Dest = SourceA & SourceB;

endmodule

module yam430_or #(
    parameter DATA_WIDTH=8
)(
    input wire [DATA_WIDTH-1 :0] SourceA,
    input wire [DATA_WIDTH-1 :0] SourceB,
    output wire [DATA_WIDTH-1 :0] Dest
);

assign Dest = SourceA | SourceB;

endmodule

module yam430_alu #(
    parameter DATA_WIDTH=8,
    parameter SEL_WIDTH=4
)(
    input wire [DATA_WIDTH-1 :0] Source,
    input wire [DATA_WIDTH-1 :0] DestIn,
    input wire CarryIn,
    input wire [SEL_WIDTH-1:0] Opcode,
    output wire CarryOut,
    output wire [DATA_WIDTH-1 :0] DestOut
);


wire [DATA_WIDTH-1:0] Source_n;
assign Source_n = ~Source;

wire [DATA_WIDTH-1:0] movOut;
assign movOut = Source;

wire [DATA_WIDTH-1:0] adderOut;
wire CarryInInt;
assign CarryInInt =  ((Opcode == ADDC) || 
        (Opcode == SUBC)) ? CarryIn : 1'b0;

wire [DATA_WIDTH-1:0] SourceBInt;
assign SourceBInt = ((Opcode == SUB) || (Opcode == SUBC)) ? Source_n : Source;

wire one;
assign one = ((Opcode == SUB) || (Opcode == SUBC)) ? 1'b1 : 1'b0;

FullAdder #(
    .DATA_WIDTH(DATA_WIDTH)
) AdderModule(
    .SourceA(Source),
    .SourceB(SourceBInt),
    .CarryIn(CarryInInt),
    .CarryOut(CarryOut),
    .one(one),
    .Dest(AdderOut)
);

wire [DATA_WIDTH-1:0] bitOut; //Dest &= source
yam430_and #(
    .DATA_WIDTH(DATA_WIDTH)
) AndModule(
    .SourceA(Source),
    .SourceB(DestIn),
    .Dest(bitOut)
);

wire [DATA_WIDTH-1:0] bicOut; //Dest &= ~Source
yam430_and #(
    .DATA_WIDTH(DATA_WIDTH)
) BicModule(
    .SourceA(Source_n),
    .SourceB(DestIn),
    .Dest(bicOut)
);

wire [DATA_WIDTH-1:0] bisOut; //Dest |= Source
yam430_or #(
    .DATA_WIDTH(DATA_WIDTH)
) OrModule(
    .SourceA(Source),
    .SourceB(DestIn),
    .Dest(bisOut)
);

wire [DATA_WIDTH-1:0] xorOut; // Dest 
yam430_xor #(
    .DATA_WIDTH(DATA_WIDTH)
) XorModule(
    .SourceA(Source),
    .SourceB(DestIn),
    .Dest(xorOut)
);

wire [(DATA_WIDTH*(2**SEL_WIDTH))-1:0] aluSelectorLine;

assign aluSelectorLine = {
    bitOut,//15 AND
    xorOut,//14 XOR
    bisOut,//13 BIS
    bicOut,//12 BIC
    {DATA_WIDTH{1'b0}},//11 BIT
    {DATA_WIDTH{1'b0}}, //10 DADD
    {DATA_WIDTH{1'b0}}, //9 CMP
    AdderOut,//8 SUB
    AdderOut,//7 SUBC
    AdderOut,//6 ADDC
    AdderOut,//5 ADD
    movOut, //4 MOV
    {DATA_WIDTH{1'b0}},//3 
    {DATA_WIDTH{1'b0}},//2
    {DATA_WIDTH{1'b0}},//1
    {DATA_WIDTH{1'b0}}//0
};

bn_mux_n_1_generate #(
    .DATA_WIDTH(DATA_WIDTH), 
    .SEL_WIDTH(SEL_WIDTH)
)  aluOutputSelect (  
        .data(aluSelectorLine),
        .sel(Opcode),
        .y(DestOut)
    );


endmodule