module IpLine(
    input wire Rst_n,
    input wire Clk,
    input wire DataZero,
    //Start new insn load process if Ack is set
    input wire OpcodeAck,
    output wire [15:0] Opcode,
    //Nen insn is loaded and can be used
    output reg OpcodeReady
);

parameter INSN_FETCH = 2'b00;
parameter IP_COUNT = 2'b01;
parameter LOOP_COUNT = 2'b10;

reg [1:0] IpLineState;
reg [1:0] NextIpLineState;


wire IpClk =  (IpLineState == IP_COUNT) ?  Clk : 1'b0;
wire LoopClk = (IpLineState == LOOP_COUNT) ? Clk : 1'b0;
wire InsnFetch = (IpLineState == INSN_FETCH) ? Clk : 1'b0;

/*
Used only for Loop Lookup mode
*/
reg IpReverse;
reg loopReverse;
/*
If 1 - Find Loop Mode
Else - Normal mode
*/
reg FindLoopMode;

wire IpForward = ~IpReverse;

wire DataNotZero = ~DataZero;

wire LoopZero;

NextOpcode nextOpcode(
        .Rst_n(Rst_n),
        .Count(IpClk),
        .Reverse(Reverse),
        .Load(InsnFetch),
        .Opcode(Opcode)
);


CounterLoop counterLoop(
    .Rst_n(Rst_n),
    .Step(LoopClk),
    .Reverse(loopReverse),
    .Zero(LoopZero)
    );


always @(negedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        IpReverse <= 1'b0;
        FindLoopMode <= 1'b0;        
        loopReverse <= 1'b0;
        IpLineState <= INSN_FETCH;
    end
    else begin
        IpLineState <= NextIpLineState;//FIXME
        case (IpLineState) 
            INSN_FETCH: begin
                if ((DataZero & Opcode[5]) | (DataNotZero & Opcode[6])) begin
                    FindLoopMode <= 1'b1;
                    NextIpLineState <= LOOP_COUNT;
                    OpcodeReady <= 1'b0;
                    IpReverse <= DataZero ? 1'b0 : 1'b1;
                    loopReverse <= ((Opcode[5] & IpForward) | (Opcode[6] & IpReverse)) ? 1'b0 : 1'b1;               
                end
                else begin
                    OpcodeReady <= FindLoopMode ? 1'b0 : 1'b1;
                    NextIpLineState <= IP_COUNT;
                end
            end
            IP_COUNT: begin
                NextIpLineState <= INSN_FETCH;
            end
            LOOP_COUNT: begin
                FindLoopMode <= LoopZero ? 1'b0 : 1'b1;
                NextIpLineState <= IP_COUNT;
            end
            default: begin
                NextIpLineState <= INSN_FETCH;
                OpcodeReady <= 1'b0;
                IpReverse <= 1'b0;
                loopReverse <= 1'b0;
            end
        endcase
    end


endmodule