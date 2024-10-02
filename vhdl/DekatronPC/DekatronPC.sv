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
    input key_next_app_i,

    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,

    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd,
    output wire tx_vld,
    input wire tx_rdy,
    
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd,
    input wire rx_vld,

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

localparam AP_RAM_ROWS_NUM = 30000;
localparam AP_RAM_BIN_BW = $clog2(AP_RAM_ROWS_NUM-1);

wire [AP_RAM_BIN_BW-1:0] ApAddressBin;
reg [AP_RAM_BIN_BW-1:0] ApAddressBin_Setup;
wire [AP_RAM_BIN_BW-1:0] ApAddressBin_Cnt;

reg ApRamRdy;

assign ApAddressBin = (ApRamRdy) ? ApAddressBin_Cnt : ApAddressBin_Setup;

BcdToBinEnc #(
    .DIGITS(AP_DEKATRON_NUM),
    .OUT_WIDTH(AP_RAM_BIN_BW)
) ApRAM_address_enc (
    .bcd(ApAddress),
    .bin(ApAddressBin_Cnt)
);

`ifdef EMULATOR
wire [AP_RAM_BIN_BW-1:0] ApAddress1Bin;
BcdToBinEnc #(
    .DIGITS(AP_DEKATRON_NUM),
    .OUT_WIDTH(AP_RAM_BIN_BW)
) ApRAM1_address_enc (
    .bcd(ApAddress1),
    .bin(ApAddress1Bin)
);
`endif

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        ApRamRdy <= 1'b0;
        ApAddressBin_Setup <= AP_RAM_ROWS_NUM - 1;
    end else begin
        if (~ApRamRdy) begin
            if (ApAddressBin_Setup != 0) begin
                ApAddressBin_Setup <= ApAddressBin_Setup - 1;
            end else begin
                ApRamRdy <= 1;
            end
        end
    end
end

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
    .key_next_app_i(key_next_app_i),
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

    .EchoMode(EchoMode),
    .IsHalted(IsHalted)
);

endmodule
