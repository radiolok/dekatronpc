module DekatronPC (
`ifdef EMULATOR
    output logic [31:0] IRET,
    /* verilator lint_off UNDRIVEN */
    input logic [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress1,
    input logic [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress1,
    /* verilator lint_on UNDRIVEN */
    /* verilator lint_off UNUSEDSIGNAL */
    output logic [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1,
    output logic [INSN_WIDTH-1:0] RomData1,
    /* verilator lint_on UNUSEDSIGNAL */

`endif
    input hsClk,
    input Clk,
    input SoftRst_n,
    input HardRst_n,
    input Halt,
    input Step,
    input Run,
    input InsnLoadingStart,
    input InsnLoadingStop,
    input keyNextIp,
    input keyPrevIp,
    input key_next_app_i,

    output logic [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output logic [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,

    output logic [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd,
    output logic tx_vld,
    input logic tx_rdy,

    input logic [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd,
    input logic rx_vld,

    output logic [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output logic [2:0] state,
    input logic [INSN_WIDTH - 1:0] InsnIn,
    input logic InsnInValid,
    output logic InsnInLoading,
    output logic InsnInReady,
    output logic [INSN_WIDTH - 1:0] Insn,

//==========================================================================
//         Switch panel section
//==========================================================================
    input logic EchoMode,//When turned on, Symbol from CIN is printed to Cout
    input logic RunOnHardRst,
    input logic RunOnSoftRst,
    input logic SoftRstOnEOT
);

logic RstExtern_n;
assign RstExtern_n = SoftRst_n & HardRst_n;

logic RstReq;
logic RstReqLong;

logic Rst_n;
assign Rst_n = RstExtern_n & ~RstReqLong;

logic IpRequest;
logic IpLineReady;

logic DataZero;
logic ApZero;

logic ApRequest;
logic DataRequest;

logic ApLineZero;

logic ApLineReady;

logic ApLineDec;
logic ApLineCin;

logic LoopValZero;
logic IsHalted;

logic InsnLoading;
logic InsnMode;

logic RomRequest;
logic RomReady;
logic RomWE;
logic [INSN_WIDTH-1:0] RomData;
logic [INSN_WIDTH-1:0] RomWriteData;

assign InsnInLoading = InsnLoading;

IpMemory
    IpRAM_ROM(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Request(RomRequest),
    .Ready(RomReady),
    .WE(RomWE),
`ifdef EMULATOR
    .Address1(IpAddress1),
    .InsnOut1(RomData1),
`endif
    .Address(IpAddress),
    .InsnIn(RomWriteData),
    .InsnOut(RomData)
);

logic [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApRamDataIn;
logic [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApRamDataOut;
logic ApRamCS;
logic ApRamWE;

localparam AP_RAM_ROWS_NUM = 30000;
localparam AP_RAM_BIN_BW = $clog2(AP_RAM_ROWS_NUM-1);

logic [AP_RAM_BIN_BW-1:0] ApAddressBin;
logic [AP_RAM_BIN_BW-1:0] ApAddressBin_Cnt;

logic ApRamRdy;

assign ApAddressBin = ApAddressBin_Cnt;

BcdToBinEnc #(
    .DIGITS(AP_DEKATRON_NUM),
    .OUT_WIDTH(AP_RAM_BIN_BW)
) ApRAM_address_enc (
    .bcd(ApAddress),
    .bin(ApAddressBin_Cnt)
);

`ifdef EMULATOR
logic [AP_RAM_BIN_BW-1:0] ApAddress1Bin;
BcdToBinEnc #(
    .DIGITS(AP_DEKATRON_NUM),
    .OUT_WIDTH(AP_RAM_BIN_BW)
) ApRAM1_address_enc (
    .bcd(ApAddress1),
    .bin(ApAddress1Bin)
);
`endif

assign ApRamRdy = 1'b1;

RAM #(
    .ROWS(AP_RAM_ROWS_NUM),
    .ADDR_WIDTH(AP_RAM_BIN_BW),
    .DATA_WIDTH(DATA_DEKATRON_NUM*DEKATRON_WIDTH)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(ApAddressBin),
    .In(ApRamDataIn),
    .Out(ApRamDataOut),
`ifdef EMULATOR
    .Address1(ApAddress1Bin),
    .Out1(ApData1),
`endif
    .WE(ApRamWE),
    .CS(ApRamCS)
);

IpLine ipLine(
    .Rst_n(Rst_n),
    .HardRst_n(HardRst_n),
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
    .InsnLoading(InsnLoading),
    .InsnLoadingStop(InsnLoadingStop),
    .InsnMode(InsnMode),
    .keyNextIp(keyNextIp),
    .keyPrevIp(keyPrevIp),
    .key_next_app_i(key_next_app_i),
    .InsnIn(InsnIn),
    .InsnInValid(InsnInValid),
    .InsnInReady(InsnInReady),
    .RomWriteData(RomWriteData),
    .RomWE(RomWE),
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
    .rx_data_bcd(rx_data_bcd),
    .Ready(ApLineReady),
    .Address(ApAddress),
    .ram_rdy_i(ApRamRdy),
    .RamDataIn(ApRamDataIn),
    .RamDataOut(ApRamDataOut),
    .RamCS(ApRamCS),
    .RamWE(ApRamWE),
    .tx_data_bcd(tx_data_bcd)
);

InsnDecoder insnDecoder(
    .Rst_n(Rst_n),
    .HardRst_n(HardRst_n),
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
    .InsnLoading(InsnLoading),
    .InsnMode(InsnMode),

    .RstReq(RstReq),

    .tx_vld(tx_vld),
    .tx_rdy(tx_rdy),
    .rx_vld(rx_vld),

    .DataZero(DataZero),
    .ApZero(ApZero),
    .LoopValZero(LoopValZero),

    .Insn(Insn),
    .state(state),

    .Halt(Halt),
    .Step(Step),
    .Run(Run),
    .InsnLoadingStart(InsnLoadingStart),
    .InsnLoadingStop(InsnLoadingStop),

    .EchoMode(EchoMode),
    .RunOnHardRst(RunOnHardRst),
    .RunOnSoftRst(RunOnSoftRst),
    .SoftRstOnEOT(SoftRstOnEOT),
    .IsHalted(IsHalted)
);

OneShot #(
    .DELAY(16),
    .IMP_ON_EN(1'b0)
) rstOneShot (
    .Clk(Clk),
    .Rst_n(RstExtern_n),
    .En(RstReq),
    .Impulse(RstReqLong)
);

endmodule
