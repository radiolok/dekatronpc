`include "parameters.sv"

module IpLine (
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,
    input wire HaltRq,

    input wire dataIsZeroed, 

    input wire Request,
    output wire Ready,
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,

    output reg RomRequest,
    input wire RomReady,
    input wire [INSN_WIDTH-1:0] RomData,

    output reg[INSN_WIDTH-1:0] Insn
);

reg IP_Request;
reg IP_Dec;
wire IP_Ready;

DekatronCounter  #(
            .D_NUM(IP_DEKATRON_NUM),
		    .WRITE(1'b0)
            )IP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(IP_Dec),
                .Set(1'b0),
                .SetZero(1'b0),
                .In({(IP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(IP_Ready),
                .Out(IpAddress),
                /* verilator lint_off PINCONNECTEMPTY */
                .Zero()
                /* verilator lint_on PINCONNECTEMPTY */
            );

//This two highligh loop insn on the ROM output to control loopLookup
wire LoopInsnOpenInternal;
wire LoopInsnCloseInternal;

InsnLoopDetector insnLoopDetectorInternal(
    .Insn(RomData),
    .LoopOpen(LoopInsnOpenInternal),
    .LoopClose(LoopInsnCloseInternal)
);

//This two highligh loop insn on the output to begin loopLookup
wire LoopInsnOpen;
wire LoopInsnClose;

InsnLoopDetector insnLoopDetector(
    .Insn(Insn),
    .LoopOpen(LoopInsnOpen),
    .LoopClose(LoopInsnClose)
);

reg Loop_Request;
reg Loop_Dec;
wire Loop_Zero;
wire Loop_Ready;

`ifdef EMULATOR
    parameter LOOP_READ = 1'b1;
`else
    parameter LOOP_READ = 1'b0;
`endif

DekatronCounter  #(
            .D_NUM(LOOP_DEKATRON_NUM),
            .READ(LOOP_READ),
		    .WRITE(1'b0)
            )Loop_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Loop_Request),
                .Dec(Loop_Dec),
                .Set(1'b0),
                .SetZero(1'b0),
                .In({(LOOP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                /* verilator lint_off PINCONNECTEMPTY */
                .Ready(Loop_Ready),
                .Out(LoopCount),
                /* verilator lint_on PINCONNECTEMPTY */
                .Zero(Loop_Zero)
            );

assign Ready = ~Request & (state == IDLE);//READY | IDLE
wire IP_backwardCount = (LoopInsnClose & ~dataIsZeroed); //backward direction for ']' & nonZero


parameter [2:0]
    IDLE      =  3'd0,
    IP_COUNT  =  3'd1,
    ROM_READ  =  3'd2,
    LOOP_COUNT = 3'd3,
    READY     =  3'd4,
    HALT      =  3'd7;

reg [2:0] state;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Insn <= {(INSN_WIDTH){1'b0}};
        IP_Dec <= 1'b0;
        IP_Request <= 1'b0;
        Loop_Request <= 1'b0;
        Loop_Dec <= 1'b0;
        state <= IDLE;
    end
    else begin
        case (state)
            IDLE:
                if (HaltRq) state <= HALT;
                else if (Request) begin
                    if (RomReady) begin
                        IP_Dec <= IP_backwardCount; //backward direction for ']' & nonZero
                        IP_Request <= 1'b1;
                        if ((LoopInsnOpen & dataIsZeroed) | 
                            (LoopInsnClose & ~dataIsZeroed)) begin
                            //Let's run loopLookup
                            Loop_Dec <= 1'b0;
                            Loop_Request <= 1'b1;
                            state <= LOOP_COUNT;
                        end
                        else 
                            state <= IP_COUNT;
                    end
                    else begin//Only for IP=0
                        state <= ROM_READ;
                        RomRequest <= 1'b1;
                    end
                end
            IP_COUNT: begin
                IP_Request <= 1'b0;
                if (IP_Ready) begin
                    state <= ROM_READ;
                    RomRequest <= 1'b1;
                end
            end
            ROM_READ: begin
                    RomRequest <= 1'b0;
                    if (RomReady) begin
                        if (Loop_Zero) begin
                            state <= READY;
                        end
                        else begin
                            if (LoopInsnOpenInternal | LoopInsnCloseInternal) begin
                                Loop_Dec <= ((IP_backwardCount & LoopInsnOpenInternal)|
                                            (~IP_backwardCount & LoopInsnCloseInternal));
                                Loop_Request <= 1'b1;
                                state <= LOOP_COUNT;
                            end
                            else begin
                                state <= IP_COUNT;  
                                IP_Dec <= IP_backwardCount; //backward direction for ']' & nonZero
                                IP_Request <= 1'b1;                         
                            end
                        end
                    end
                end
            LOOP_COUNT: begin
                Loop_Request <= 1'b0;
                if (Loop_Ready) begin
                    if ((LoopInsnOpenInternal | LoopInsnCloseInternal)) begin
                        IP_Dec <= IP_backwardCount & ~Loop_Zero; //backward direction for ']' & nonZero
                        IP_Request <= 1'b1;    
                    end
                    state <= IP_COUNT;
                end
            end
            READY: begin
                Insn <= RomData;
                if (~Request) begin
                    state <= IDLE;
                end
            end
            HALT: begin
                if (HaltRq)
                    state <= HALT;
                else
                    state <= IDLE;
            end
            default:
                state <= IDLE;
        endcase
    end
end

endmodule
