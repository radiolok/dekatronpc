`include "parameters.sv"

module DekatronPC (
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
    output reg [2:0] state
);

reg IpRequest;
wire IpLineReady;

wire [INSN_WIDTH - 1:0] Insn;
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

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .HaltRq(IsHalted),
    .dataIsZeroed(LoopValZero),
    .Request(IpRequest),
	.Ready(IpLineReady),
    .Address(IpAddress),
    .LoopCount(LoopCount),
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
                        4'b0000: begin//NOP
                            state <= FETCH;
                            IpRequest <= 1'b1;
                        end
                        4'b0001: begin//HALT
                            state <= HALT;
                        end
                        4'b001?: begin
                            if (InsnMode == BRAINFUCK_ISA) begin
                                state <= EXEC;
                                DataRequest <= 1'b1;
                                ApRequest <= 1'b0;
                                ApLineDec <= Insn[0];
                            end
                        end
                        4'b010?: begin
                            if (InsnMode == BRAINFUCK_ISA) begin
                                state <= EXEC;
                                DataRequest <= 1'b0;
                                ApRequest <= 1'b1;
                                ApLineDec <= Insn[0];
                            end
                        end
                        4'b1000: begin
                            Cout <= 1'b1;
                            state <= FETCH;
                            IpRequest <= 1'b1;
                        end
                        4'b1110: begin
                            InsnMode <= DEBUG_ISA;
                        end
                        4'b1111: begin
                            InsnMode <= BRAINFUCK_ISA;
                        end
                        default: begin
                            state <= IDLE;
                            IpRequest <= 1'b1;
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
