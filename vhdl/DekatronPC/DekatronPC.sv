module DekatronPC (
`ifdef EMULATOR
    output reg [31:0] IRET,
`endif
    input hsClk,
    input Clk,
    input Rst_n, 
    input Halt,
    input Step,
    input Run,
    output reg Cout,
    input wire CioAcq,
    output reg CinReq,

    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,

    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCin,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output reg [2:0] state,
    output wire [INSN_WIDTH - 1:0] Insn,

//==========================================================================
//         Switch panel section
//==========================================================================
    input wire EchoMode//When turned on, Symbol from CIN is printed to Cout

);

reg IpRequest;
wire IpLineReady;


reg InsnMode;

wire DataZero;
wire ApZero;

reg ApRequest = 1'b0;
reg DataRequest = 1'b0;

reg ApLineZero;

wire ApLineReady;

reg ApLineDec;
reg ApLineCin;

//If Debug mode {} check AP 
//In brainfuck mode [] check *AP
wire LoopValZero = InsnMode ? DataZero : ApZero;

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

reg OneStep;
reg Echo;

parameter [2:0]
    IDLE     =  3'b001,
    FETCH     =  3'b0010,
    EXEC    =  3'b011,
    HALT    =  3'b100,
    CIN     =  3'b101,
    COUT    =  3'b110,
    CIO_ACQ    =  3'b111;

assign IsHalted = (state == HALT);

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Cout <= 1'b0;
        IpRequest <= 1'b0;
        ApLineDec <= 1'b0;
        ApLineCin <= 1'b0;
        ApRequest <= 1'b0;
        DataRequest <= 1'b0;
        ApLineZero <= 1'b0; 
        OneStep <= 1'b0;
        state <= HALT;
        InsnMode <= BRAINFUCK_ISA;//FIX: Debug mode must be by default.
`ifdef EMULATOR        
        IRET <= 0;
`endif
    end
    else begin
        case (state)
            IDLE: begin
                if (Halt) begin
                    state <= HALT;
                end
                state <= FETCH;
                IpRequest <= 1'b1;
            end
            FETCH: begin
                IpRequest <= 1'b0;
                Cout <= 1'b0;
                if (IpLineReady) begin
                    casez ({InsnMode,Insn})
                        5'h?0: state <= IDLE;  //INSN_NOP
                        5'h?1: state <= HALT; //INSN_HALT
                        //5'h02: //INSN_RES0
                        //5'h03: //INSN_RES1
                        //5'h04: //INSN_RES2
                        //5'h05: //INSN_RES3
                        5'h?6: begin //[ { 
                            if (LoopValZero) begin
                                IpRequest <= 1'b1;
                            end
                            else begin
                                state <= EXEC;
                            end
                        end
                        5'h?7: begin //] }
                            if (~LoopValZero) begin
                                IpRequest <= 1'b1;
                            end
                            else begin
                                state <= EXEC;
                            end
                        end
                        //5'h08:  //INSN_CLRL
                        //5'h09:  //INSN_CLRI
                        5'h?A: begin//INSN_CLRD
                                ApRequest <= 1'b0;
                                DataRequest <= 1'b1;
                                ApLineZero <= 1'b1;
                                state <= EXEC;
                            end 
                        5'h0B:  begin//INSN_CLRA
                                ApRequest <= 1'b1;
                                ApLineZero <= 1'b1;
                                DataRequest <= 1'b0;
                                state <= EXEC;
                            end 
                        //5'h0C:  //INSN_RES4
                        //5'h0D:  //INSN_RST
                        5'b1001?: begin//+ -
                                ApRequest <= 1'b0;
                                DataRequest <= 1'b1;
                                ApLineDec <= Insn[0];
                                state <= EXEC;
                            end
                        5'b1010?:  begin//< > 
                                ApRequest <= 1'b1;
                                DataRequest <= 1'b0;
                                ApLineDec <= Insn[0];
                                state <= EXEC;
                            end
                        5'h18:   begin //INSN_COUT
                            Cout <= 1'b1;
                            state <= COUT;
                        end
                        5'h19:  begin //INSN_CIN
                            CinReq <= 1'b1;
                            state <= CIN;
                        end
                        //5'h1A:   //INSN_CLRD?
                        //5'h1B:   //INSN_CLRML
                        //5'h1C:   //INSN_LOAD
                        //5'h1D:   //INSN_STORE
                        5'h?E: begin //INSN_DEBUG
                            InsnMode <= DEBUG_ISA;
                            state <= EXEC;
                        end
                        5'h?F: begin //INSN_BRAINFUCK
                            InsnMode <= BRAINFUCK_ISA;
                            state <= EXEC;
                        end
                        default: begin
                            state <= EXEC;
                        end
                    endcase
                end
            end
            EXEC: begin
                DataRequest <= 1'b0;
                ApRequest <= 1'b0;
                ApLineZero <= 1'b0;
                ApLineCin <= 1'b0;
                if (ApLineReady) begin
                    if (Halt | OneStep) begin
                        state <= HALT;
                        OneStep <= 1'b0;
                    end
                    else begin
                        state <= FETCH;
                        IpRequest <= 1'b1;
                    end
                    `ifdef EMULATOR
                        IRET <= IRET + 1;
                    `endif 
                end
            end
            CIN: begin
                if (CioAcq) begin;
                    DataRequest <= 1'b1;
                    ApLineCin <= 1'b1;
                    CinReq <= 1'b0;
                    state <= CIO_ACQ;
                    if (EchoMode)
                        Echo <= 1'b1;
                end
            end
            COUT: begin
                if (CioAcq) begin
                    Cout <= 1'b0;
                    state <= CIO_ACQ;
                end
            end
            CIO_ACQ: begin
                DataRequest <= 1'b0;
                ApLineCin <= 1'b0;
                if (ApLineReady & ~CioAcq) begin
                    if (Echo) begin
                        Echo <= 1'b0;
                        Cout <= 1'b1;
                        state <= COUT;
                    end
                    else begin
                        state <= EXEC;
                    end
                end
            end
            HALT: begin
                if (Step | Run) begin
                    state <= IDLE;
                    if (Step)
                        OneStep <= 1'b1;
                end
                else begin
                    state <= HALT;
                end
            end
            default: begin
                state <= IDLE;
            end
        endcase
    end

end
endmodule
