module IpLine #(
    parameter IP_DEKATRON_NUM = 6,
    parameter LOOP_DEKATRON_NUM = 3,
    parameter DEKATRON_WIDTH = 4,
    parameter INSN_WIDTH = 4
)(
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,

    input wire dataIsZeroed, 

    input wire Request,
    output wire Ready,
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,
    output reg[3:0] Insn
);


reg IP_Dec;

reg IP_Request;
wire IP_Ready;

wire [INSN_WIDTH-1:0] TmpInsnReg;

IpCounter IP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(IP_Dec),
                .Ready(IP_Ready),
                .Address(Address),
                .Insn(TmpInsnReg)
            );

//This two highligh loop insn on the ROM output to control loopLookup
wire LoopInsnOpenInternal;
wire LoopInsnCloseInternal;

//This two highligh loop insn on the output to begin loopLookup
wire LoopInsnOpen;
wire LoopInsnClose;

InsnLoopDetector #(
    .DATA_WIDTH(INSN_WIDTH)
)insnLoopDetectorInternal(
    .Insn(TmpInsnReg),
    .LoopOpen(LoopInsnOpenInternal),
    .LoopClose(LoopInsnCloseInternal)
);

InsnLoopDetector #(
    .DATA_WIDTH(INSN_WIDTH)
    )insnLoopDetector(
    .Insn(Insn),
    .LoopOpen(LoopInsnOpen),
    .LoopClose(LoopInsnClose)
);

reg Loop_Request;
wire Loop_Ready;

reg Loop_Dec;

wire Loop_Zero;

DekatronCounter  #(
            .D_NUM(LOOP_DEKATRON_NUM),
            .D_WIDTH(DEKATRON_WIDTH)
            )Loop_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Loop_Request),
                .Dec(Loop_Dec),
                .Set(1'b0),
                .In({(LOOP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(Loop_Ready),
                /* verilator lint_off PINCONNECTEMPTY */
                .Out(),
                /* verilator lint_on PINCONNECTEMPTY */
                .Zero(Loop_Zero)
            );

parameter [3:0]
    IDLE     =  4'b0001,
    INSN_WAIT =  4'b0010,
    LOOP_COUNT = 4'b0100,
    READY     = 4'b1000;

reg [3:0] currentState;
assign Ready = currentState[3] | currentState[0];//READY | IDLE
wire IP_backwardCount = (LoopInsnClose & ~dataIsZeroed); //backward direction for ']' & nonZero

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Insn <= {(INSN_WIDTH){1'b0}};
        IP_Dec <= 1'b0;
        IP_Request <= 1'b0;
        Loop_Request <= 1'b0;
        Loop_Dec <= 1'b0;
        currentState <= IDLE;
    end
    else begin
        case (currentState)
            IDLE:
                if (Request) begin
                    IP_Dec <= IP_backwardCount; //backward direction for ']' & nonZero
                    IP_Request <= 1'b1;
                    if ((LoopInsnOpen & dataIsZeroed) | (LoopInsnClose & ~dataIsZeroed)) begin
                        //Let's run loopLookup
                        Loop_Dec <= 1'b0;
                        Loop_Request <= 1'b1;
                        currentState <= LOOP_COUNT;
                    end
                    else begin
                        currentState <= INSN_WAIT;
                    end
                end
            INSN_WAIT: begin
                    IP_Request <= 1'b0;
                    if (IP_Ready) begin
                        if (Loop_Zero) begin
                            currentState <= READY;
                            Insn <= TmpInsnReg;
                        end
                        else begin
                            if (LoopInsnOpenInternal | LoopInsnCloseInternal) begin
                                Loop_Dec <= ((IP_backwardCount & LoopInsnOpenInternal)|(~IP_backwardCount & LoopInsnCloseInternal));
                                Loop_Request <= 1'b1;
                                currentState <= LOOP_COUNT;
                            end
                            else begin
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
                    currentState <= INSN_WAIT;
                end
            end
            READY:
                if (~Request) begin
                    currentState <= IDLE;
                end
            default:
                currentState <= IDLE;
        endcase
    end
end
endmodule
