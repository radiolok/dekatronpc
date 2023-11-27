module DekatronPC (
`ifdef EMULATOR
    output wire [31:0] IRET,
`endif
    input hsClk,
    input Clk,
    input Rst_n, 
    input Halt,
    input Step,
    input Run,
    output wire Cout,
    input wire CioAcq,
    output wire CinReq,

    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,

    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCin,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output wire [2:0] state,
    output wire [INSN_WIDTH - 1:0] Insn,

//==========================================================================
//         Switch panel section
//==========================================================================
    input wire EchoMode//When turned on, Symbol from CIN is printed to Cout
);

wire IpRequest;
wire IpLineReady;

wire DataZero;
wire ApZero;

wire ApRequest;
wire DataRequest;

wire ApLineZero;

wire ApLineReady;

wire ApLineDec;
wire ApLineCin;

wire LoopValZero;
wire IsHalted;

wire RomRequest;
wire RomReady;
wire [INSN_WIDTH-1:0] RomData;

ROM #(
        .D_NUM(IP_DEKATRON_NUM),
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(IpAddress),
        .Insn(RomData),
        .Request(RomRequest),
        .Ready(RomReady)
        );

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataIn;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataOut;
wire RamCS;
wire RamWE;

`ifdef EMULATOR
/* verilator lint_off UNDRIVEN */
    wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress1;
/* verilator lint_on UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1;
/* verilator lint_on UNUSEDSIGNAL */
`endif

RAM #(
    .ROWS(21'h100000),
    .ADDR_WIDTH(AP_DEKATRON_NUM*DEKATRON_WIDTH),
    .DATA_WIDTH(DATA_DEKATRON_NUM*DEKATRON_WIDTH)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(ApAddress),
    .In(RamDataIn),
    .Out(RamDataOut),
`ifdef EMULATOR
    .Address1(ApAddress1),
    .Out1(ApData1),
`endif
    .WE(RamWE),
    .CS(RamCS)
);

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .HaltRq(IsHalted),
    .dataIsZeroed(LoopValZero),
    .Request(IpRequest),
	.Ready(IpLineReady),
    .IpAddress(IpAddress),
    .LoopCount(LoopCount),
    .RomRequest(RomRequest),
    .RomReady(RomReady),
    .RomData(RomData),
	.Insn(Insn)
);

ApLine  apLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .DataZero(DataZero),
    .ApZero(ApZero),
    .ApRequest(ApRequest),
    .DataRequest(DataRequest),
    .Dec(ApLineDec),
    .Zero(ApLineZero),
    .Cin(ApLineCin),
    .DataCin(DataCin),
    .Ready(ApLineReady),
    .Address(ApAddress),
    .RamDataIn(RamDataIn),
    .RamDataOut(RamDataOut),
    .RamCS(RamCS),
    .RamWE(RamWE),
    .Data(Data)
);

InsnDecoder insnDecoder(
    .Rst_n(Rst_n),
    .Clk(Clk),
`ifdef EMULATOR
    .IRET(IRET),
`endif

    .IpRequest(IpRequest),    
    .IpLineReady(IpLineReady),
    .ApLineReady(ApLineReady),
    .ApRequest(ApRequest),
    .ApLineDec(ApLineDec),
    .ApLineCin(ApLineCin),
    .ApLineZero(ApLineZero),
    .DataRequest(DataRequest),

    .CioAcq(CioAcq),
    .Cout(Cout),
    .CinReq(CinReq),
    .DataZero(DataZero),
    .ApZero(ApZero),
    .LoopValZero(LoopValZero),

    .Insn(Insn),
    .state(state),

    .Halt(Halt),
    .Step(Step),
    .Run(Run),

    .EchoMode(EchoMode),
    .IsHalted(IsHalted)
);

endmodule
