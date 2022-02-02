module IpCounter #(
    parameter DEKATRON_NUM = 6,
    parameter DEKATRON_WIDTH = 3,
    parameter COUNT_DELAY = 3,//delay in clockticks between Req and Rdy
    parameter INSN_WIDTH = 4
)(	
	input wire Clk,
	input wire Rst_n,

    // All changes start on Request
    //If Set == 1, Out <= In
    //If Dec = 1, Out <= Out-1
    //Else, Out <= Out + 1
    input wire Request,
    input wire Dec,

	output wire Ready,
	output wire[INSN_WIDTH-1:0] Insn
);

reg IP_Request;
wire IP_Ready;
wire [DEKATRON_NUM*3-1:0] IP_Out;

Counter  #(
            .DEKATRON_NUM(DEKATRON_NUM),
            .DEKATRON_WIDTH(DEKATRON_WIDTH),
            .COUNT_DELAY(COUNT_DELAY)
            )IP_counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(Dec),
                .Set(1'b0),
                .Ready(IP_Ready),
                .Out(IP_Out)
            );

reg ROM_Request;
wire ROM_DataReady;

ROM #(
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(IP_Out),
        .Insn(Insn),
        .Request(ROM_Request),
        .DataReady(ROM_DataReady)
        );

parameter [3:0]
    IDLE     =  4'b0001,
    IP_COUNT =  4'b0010,
    ROM_COUNT = 4'b0100,
    READY     = 4'b1000;

reg [3:0] currentState;
assign Ready = currentState[3] | currentState[0];//READY | IDLE

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        IP_Request <= 1'b0;
        ROM_Request <= 1'b0;
        currentState <= IDLE;
    end
    else begin
        case (currentState)
            IDLE:
                if (Request) begin
                    if (ROM_DataReady) begin
                        IP_Request <= 1'b1;
                        currentState <= IP_COUNT;
                    end
                    else begin
                        ROM_Request <= 1'b1;
                        currentState <= ROM_COUNT;
                    end
                end
            IP_COUNT: begin
                IP_Request <= 1'b0;
                if (IP_Ready & Clk) begin
                    ROM_Request <= 1'b1;
                    currentState <= ROM_COUNT;
                end
            end
            ROM_COUNT: begin                
                ROM_Request <= 1'b0;
                if (ROM_DataReady & Clk) begin
                    currentState <= READY;
                end
            end
            READY:
                if (~Request) begin
                    currentState <= IDLE;
                end
        endcase        
    end    
end
endmodule


module IpLine(
    input wire Rst_n,
    input wire Clk,

    input wire dataIsZeroed, 

    input wire Request,
    output wire Ready,

    output reg[3:0] Insn
);

parameter IP_DEKATRON_NUM = 6;
parameter LOOP_DEKATRON_NUM = 3;
parameter DEKATRON_WIDTH = 3;
parameter INSN_WIDTH = 4;

reg IP_Dec;

reg IP_Request;
wire IP_Ready;

wire [IP_DEKATRON_NUM*3-1:0] IP_Out;
wire [INSN_WIDTH-1:0] TmpInsnReg;

IpCounter IP_counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(IP_Dec),
                .Ready(IP_Ready),
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

wire [LOOP_DEKATRON_NUM*3-1:0] Loop_Out;
wire Loop_Zero = (Loop_Out == {(LOOP_DEKATRON_NUM*3){1'b0}});

wire Loop_Lookup = ~(Loop_Ready & Loop_Zero);

Counter  #(
            .DEKATRON_NUM(LOOP_DEKATRON_NUM),
            .DEKATRON_WIDTH(DEKATRON_WIDTH),
            .COUNT_DELAY(3)
            )Loop_counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(Loop_Request),
                .Dec(Loop_Dec),
                .Set(1'b0),
                .Ready(Loop_Ready),
                .Out(Loop_Out)
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
                        if (~Loop_Lookup) begin
                            currentState <= READY;
                            Insn <= TmpInsnReg;
                        end
                        else begin
                            IP_Dec <= IP_backwardCount; //backward direction for ']' & nonZero
                            IP_Request <= 1'b1;
                            if (LoopInsnOpenInternal | LoopInsnCloseInternal) begin
                                Loop_Dec <= ((IP_backwardCount & LoopInsnOpenInternal)|(~IP_backwardCount & LoopInsnCloseInternal));
                                Loop_Request <= 1'b1;
                                currentState <= LOOP_COUNT;
                            end

                        end
                    end
                end
            LOOP_COUNT: begin
                Loop_Request <= 1'b0;
                if (Loop_Ready) begin
                    currentState <= INSN_WAIT;
                end
            end
            READY:
                if (~Request) begin
                    currentState <= IDLE;
                end
        endcase
    end
end

endmodule