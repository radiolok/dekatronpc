module IpLine(
    input wire Rst_n,
    input wire Clk,
    input wire DataZero,
    //Start new insn load process if Ack is set
    input wire OpcodeAck,
    output wire [15:0] Opcode,
    //Nen insn is loaded and can be used
    output wire OpcodeReady
);

parameter NONE = 2'b00;
parameter INSN_FETCH = 2'b01;
parameter IP_COUNT = 2'b10;
parameter LOOP_COUNT = 2'b11;

wire LoopZero;
wire IpReady;
wire LoopReady;

reg [1:0] IpLineState;

wire IpClk =  (IpLineState[1] & ~IpLineState[0]) ?  Clk : 1'b0;
wire LoopClk = (IpLineState[1] & IpLineState[0]) ?  Clk : 1'b0;
wire InsnFetch = (~IpLineState[1] & IpLineState[0]) ? Clk & (LoopReady & IpReady): 1'b0;

/*
Used only for Loop Lookup mode
*/
wire IpReverse;
wire loopReverse;
/*
If 1 - Find Loop Mode
Else - Normal mode
*/
reg FindLoopMode;

wire IpForward = ~IpReverse;

wire DataNotZero = ~DataZero;

wire[23:0] IpAddress;

CounterIp IP(.Clk(IpClk),
            .Reverse(IpReverse), 
            .Rst_n(Rst_n), 
            .Out(IpAddress),
            .Ready(IpReady));

wire [3:0] Insn;

ROM rom(.Rst_n(Rst_n),
        .Clk(InsnFetch), 
        .Address(IpAddress),
        .Insn(Insn));

OpcodeDecoder opcodeDecoder(.Insn(Insn),
                            .Opcode(Opcode));


CounterLoop counterLoop(
    .Rst_n(Rst_n),
    .Clk(LoopClk),
    .Reverse(loopReverse),
    .Zero(LoopZero),
    .Ready(LoopReady)
    );


wire loopSkipCase = Opcode[5] & DataZero;
wire loopIterCase = Opcode[6] & ~DataZero;
wire loopCornerCase = loopSkipCase | loopIterCase;
wire loopOpcode = (Opcode[5]) || (Opcode[6]);

wire IpLineStateNone = ~IpLineState[1] & ~IpLineState[0];
wire IpLineStateInsnFetch = ~IpLineState[1] & IpLineState[0];
wire IpLineStateIpCount = IpLineState[1] & ~IpLineState[0];
wire IpLineStateLoopCount = IpLineState[1] & IpLineState[0];

assign OpcodeReady = IpLineStateNone & ~FindLoopMode & LoopReady & IpReady;
assign loopReverse =  ~loopCornerCase; 
assign IpReverse = FindLoopMode & ~DataZero;


always @(negedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        FindLoopMode <= 1'b0;
        IpLineState <= INSN_FETCH;
    end
    else begin
        if (IpLineStateInsnFetch & ~FindLoopMode & loopCornerCase)
            FindLoopMode <= 1'b1;
        if (IpLineStateLoopCount)
            FindLoopMode <= ~LoopZero;
        IpLineState <= (OpcodeAck & IpLineStateNone)? INSN_FETCH :
        IpLineStateInsnFetch ? (((loopOpcode & FindLoopMode) | (loopCornerCase)) ? LOOP_COUNT : IP_COUNT) :
                                            IpLineStateLoopCount ? IP_COUNT : NONE;
    end


endmodule