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
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output reg [2:0] state,
    output wire [INSN_WIDTH - 1:0] Insn
);

reg IpRequest;
wire IpLineReady;


reg InsnMode;

wire DataZero;
wire ApZero;

reg ApRequest = 1'b0;
reg DataRequest = 1'b0;

wire ApLineReady;

reg ApLineDec;

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

RAM #(
    .ROWS(170393),
    .DATA_WIDTH(12)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(ApAddress[17:0]),
    .In(RamDataIn),
    .Out(RamDataOut),
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
    .Ready(ApLineReady),
    .Address(ApAddress),
    .RamDataIn(RamDataIn),
    .RamDataOut(RamDataOut),
    .RamCS(RamCS),
    .RamWE(RamWE),
    .Data(Data)
);

reg OneStep;

parameter [2:0]
    IDLE     =  3'b001,
    FETCH     =  3'b0010,
    EXEC    =  3'b011,
    HALT    =  3'b100;

assign IsHalted = (state == HALT);

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Cout <= 1'b0;
        IpRequest <= 1'b0;
        ApLineDec <= 1'b0;
        ApRequest <= 1'b0;
        DataRequest <= 1'b0;
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
                    casez (Insn)
                        4'b0001: begin//HALT
                            state <= HALT;
                        end
                        4'b001?: begin//+-
                            if (InsnMode == BRAINFUCK_ISA) begin
                                DataRequest <= 1'b1;
                                ApRequest <= 1'b0;
                                ApLineDec <= Insn[0];
                                state <= EXEC;
                            end
                        end
                        4'b010?: begin//<>
                            if (InsnMode == BRAINFUCK_ISA) begin
                                DataRequest <= 1'b0;
                                ApRequest <= 1'b1;
                                ApLineDec <= Insn[0];
                                state <= EXEC;
                            end
                        end
                        4'b0110: begin //[
                            if (LoopValZero) begin
                                IpRequest <= 1'b1;
                            end
                            else begin
                                state <= EXEC;
                            end
                        end
                        4'b0111: begin //]
                            if (~LoopValZero) begin
                                IpRequest <= 1'b1;
                            end
                            else begin
                                state <= EXEC;
                            end
                        end
                        4'b1110: begin
                            InsnMode <= DEBUG_ISA;
                            state <= EXEC;
                        end
                        4'b1111: begin
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
