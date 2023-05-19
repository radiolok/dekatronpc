`include "parameters.sv"

module IpLine (
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,
    input wire HaltRq,

    input wire dataIsZeroed, 

    input wire Request,
    output wire Ready,
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,

`ifdef RAM_TWO_PORT
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address1,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data1,
`endif

    output reg[INSN_WIDTH-1:0] Insn
);

wire [INSN_WIDTH-1:0] TmpInsnReg;

wire IP_Request;
wire IP_Dec;
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
                .In({(IP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(IP_Ready),
                .Out(Address),
                /* verilator lint_off PINCONNECTEMPTY */
                .Zero()
                /* verilator lint_on PINCONNECTEMPTY */
            );

wire ROM_Request;
wire ROM_DataReady;

ROM #(
        .D_NUM(IP_DEKATRON_NUM),
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(Address),
        .Insn(TmpInsnReg),
        .Request(ROM_Request),
        .Ready(ROM_DataReady)
        );

//This two highligh loop insn on the ROM output to control loopLookup
wire LoopInsnOpenInternal;
wire LoopInsnCloseInternal;

InsnLoopDetector insnLoopDetectorInternal(
    .Insn(TmpInsnReg),
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

wire Loop_Request;
wire Loop_Dec;
wire Loop_Zero;

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
                .In({(LOOP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                /* verilator lint_off PINCONNECTEMPTY */
                .Ready(),
                .Out(LoopCount),
                /* verilator lint_on PINCONNECTEMPTY */
                .Zero(Loop_Zero)
            );

parameter [2:0]
    IDLE      =  3'd0,
    IP_COUNT  =  3'd1,
    ROM_READ  =  3'd2,
    LOOP_COUNT = 3'd3,
    READY     =  3'd4,
    HALT      =  3'd7;

reg [2:0] state, next;

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) state <= 0;
	else state <= next;
end

always_comb begin
    case (state)
    IDLE: begin
        if (HaltRq) next = HALT;
        else begin
            if (Request) begin
                if ((LoopInsnOpen & dataIsZeroed) | 
                    (LoopInsnClose & ~dataIsZeroed)) next = LOOP_COUNT;
                else 
                    if (ROM_DataReady)
                        next = IP_COUNT;
                    else//Only for IP=0
                        next = ROM_READ;
            end
            else next = IDLE;
        end
    end
    IP_COUNT: begin
        if (IP_Ready) next = ROM_READ;
        else next = IP_COUNT;
    end
    ROM_READ: begin
        if (HaltRq) next = HALT;
        else begin
            if (ROM_DataReady) begin
                if (Loop_Zero) 
                    next = READY;
                else begin
                    if (LoopInsnOpenInternal | LoopInsnCloseInternal)
                        next = LOOP_COUNT;
                    else
                        next = IP_COUNT;
                end
            end
            else
                next = ROM_READ;
        end
    end
    LOOP_COUNT: begin
        if (IP_Ready)
            next = ROM_READ;
        else
            next = IP_COUNT;
    end
    HALT: begin
        if (HaltRq)
            next = HALT;
        else
            next = IDLE;
    end
    READY:
        next = IDLE;
    default:
        next = IDLE;
    endcase
end

assign Ready = ~Request & (state == IDLE);//READY | IDLE
wire IP_backwardCount = (LoopInsnClose & ~dataIsZeroed); //backward direction for ']' & nonZero


assign IP_Request = (state == IP_COUNT) | (state == LOOP_COUNT);
assign IP_Dec = IP_backwardCount & ((state == IP_COUNT)& (~Loop_Zero) | (state == LOOP_COUNT));

assign ROM_Request = (state == ROM_READ);

assign Loop_Request = (state == LOOP_COUNT);
assign Loop_Dec = Loop_Request & ((IP_backwardCount & LoopInsnOpenInternal)|
                                (~IP_backwardCount & LoopInsnCloseInternal));

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Insn <= {(INSN_WIDTH){1'b0}};
    end
    else begin
        if (state == READY) Insn <= TmpInsnReg;
    end
end
endmodule
