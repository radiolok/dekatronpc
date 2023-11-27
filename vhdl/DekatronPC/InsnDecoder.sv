module InsnDecoder(
    input wire Clk,
    input wire Rst_n,

    input wire Halt,
    input wire Step,
    input wire Run,
`ifdef EMULATOR
    output reg [31:0] IRET,
`endif

    input wire [INSN_WIDTH - 1:0] Insn,
    input wire IpLineReady,
    input wire ApLineReady,

    input wire DataZero,
    input wire ApZero,
    output wire LoopValZero,

    output reg ApRequest,
    output reg ApLineCin,
    output reg ApLineDec,
    output reg ApLineZero,
    output reg IpRequest,
    output reg DataRequest,

    input wire CioAcq,
    output reg CinReq,
    output reg Cout,

    output reg [2:0] state,

    output wire IsHalted,

    //==========================================================================
//         Switch panel section
//==========================================================================
    input wire EchoMode//When turned on, Symbol from CIN is printed to Cout
);

assign IsHalted = (state == HALT);

//If Debug mode {} check AP 
//In brainfuck mode [] check *AP
assign LoopValZero = InsnMode ? DataZero : ApZero;

reg OneStep;
reg Echo;
reg InsnMode;

parameter [2:0]
    IDLE     =  3'b001,
    FETCH     =  3'b0010,
    EXEC    =  3'b011,
    HALT    =  3'b100,
    CIN     =  3'b101,
    COUT    =  3'b110,
    CIO_ACQ    =  3'b111;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Cout <= 1'b0;
        CinReq <= 1'b0;
        Echo <= 1'b0;
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
