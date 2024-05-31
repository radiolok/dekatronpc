module DekatronPC (
`ifdef EMULATOR
    output wire [31:0] IRET,
    /* verilator lint_off UNDRIVEN */
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress1,
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress1,
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_off UNUSEDSIGNAL */
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1,
    output wire [INSN_WIDTH-1:0] RomData1,
    /* verilator lint_on UNUSEDSIGNAL */

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
    input wire [INSN_WIDTH - 1:0] InsnIn,
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

IpMemory 
    IpRAM_ROM(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Request(RomRequest),
    .Ready(RomReady),
    .WE(1'b0),
`ifdef EMULATOR
    .Address1(IpAddress1),
    .InsnOut1(RomData1),
`endif
    .Address(IpAddress),
    .InsnIn(InsnIn),
    .InsnOut(RomData)
);

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApRamDataIn;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApRamDataOut;
wire ApRamCS;
wire ApRamWE;


RAM #(
    .ROWS(21'h100000),
    .ADDR_WIDTH(AP_DEKATRON_NUM*DEKATRON_WIDTH),
    .DATA_WIDTH(DATA_DEKATRON_NUM*DEKATRON_WIDTH)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(ApAddress),
    .In(ApRamDataIn),
    .Out(ApRamDataOut),
`ifdef EMULATOR
    .Address1(ApAddress1),
    .Out1(ApData1),
`endif
    .WE(ApRamWE),
    .CS(ApRamCS)
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
    .RamDataIn(ApRamDataIn),
    .RamDataOut(ApRamDataOut),
    .RamCS(ApRamCS),
    .RamWE(ApRamWE),
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
