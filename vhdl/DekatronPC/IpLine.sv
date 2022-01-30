module IpLine(
    input wire Rst_n,
    input wire Clk,
   
);

reg IP_Request;
reg IP_Dec;
reg IP_Set;
reg [DEKATRON_NUM*3-1:0] IP_In;

wire IP_Ready;

wire [DEKATRON_NUM*3-1:0] IP_Out;

Counter  #(.DEKATRON_NUM(6),
            .COUNT_DELAY(3))
            IP_counter(
                .Clk(Clk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(IP_Dec),
                .Set(IP_Set),
                .In(IP_In),
                .Ready(IP_Ready),
                .Out(IP_Out)
            );

ROM rom(.Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(IP_Out),
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