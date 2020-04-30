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
reg IpReverse;
reg loopReverse;
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


always @(negedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        IpReverse <= 1'b0;
        FindLoopMode <= 1'b0;        
        loopReverse <= 1'b0;
        IpLineState <= INSN_FETCH;
    end
    else begin
        case (IpLineState) 
            INSN_FETCH: begin
                if (FindLoopMode) begin
                    if ((Opcode[5]) || (Opcode[6])) begin
                        IpLineState <= LOOP_COUNT;
                        loopReverse <= ((Opcode[5] & DataZero) | (Opcode[6] & ~DataZero)) ? 1'b0 : 1'b1; 
                    end
                    else begin
                        OpcodeReady <= ~FindLoopMode;
                        IpLineState <= IP_COUNT;
                    end
                end
                else begin
                    if ((DataZero & Opcode[5]) | (DataNotZero & Opcode[6])) begin
                        FindLoopMode <= 1'b1;
                        IpLineState <= LOOP_COUNT;
                        OpcodeReady <= 1'b0;
                        IpReverse <= ~DataZero;
                        loopReverse <= ((Opcode[5] & DataZero) | (Opcode[6] & ~DataZero)) ? 1'b0 : 1'b1;               
                    end
                    else begin
                        OpcodeReady <= ~FindLoopMode;
                        IpLineState <= IP_COUNT;
                    end
                end
            end
            IP_COUNT: begin
                IpLineState <= INSN_FETCH;
            end
            LOOP_COUNT: begin
                FindLoopMode <= ~LoopZero;
                if (IpReverse & LoopZero)
                    IpReverse <= 1'b0;
                IpLineState <= IP_COUNT;
            end
            default: begin
                IpLineState <= INSN_FETCH;
                OpcodeReady <= 1'b0;
                IpReverse <= 1'b0;
                loopReverse <= 1'b0;
            end
        endcase
    end


endmodule