module ApLine(
    input wire Clk,
    input wire Rst_n,
    input wire ApCountAck,
    input wire DataCountAck,
    input wire DataWriteAck,
    input wire CounterReverse,
    output wire Ready,
    output reg ApCounterLock,
    input wire[9:0] DataIn,
    output wire[9:0] DataOut
);

wire[19:0] ApAddress;
parameter NONE = 3'b000;
parameter DATA_LOAD = 3'b001;
parameter DATA_COUNT = 3'b010;
parameter DATA_STORE = 3'b011;
parameter AP_COUNT = 3'b100;

reg [2:0] LastApLineState;
reg [2:0] NextApLineState;

wire ApClk = (LastApLineState == AP_COUNT) & Clk;
wire DataClk = (LastApLineState == DATA_COUNT) & Clk;

wire [9:0] RamOutCntrIn;
wire [9:0] RamInCntrOut;

wire [9:0] RamDataIn = DataWriteAck ? DataIn : RamInCntrOut;
assign  DataOut = ApCounterLock ? RamInCntrOut : RamOutCntrIn;

wire RamCs = 1'b1;
wire Ram_WE_n = (LastApLineState == DATA_STORE);

wire DataReady;
wire ApReady;
wire DataSet;

CounterAp AP(.Step(ApClk),
            .Rst_n(Rst_n), 
            .Reverse(CounterReverse),
            .Ready(ApReady),
            .Out(ApAddress));

RAM ram(.Address(ApAddress), 
        .In(RamDataIn), 
        .Out(RamOutCntrIn), 
        .CS(RamCs), 
        .WE_n(Ram_WE_n), 
        .Clk(Clk),
        .Rst_n(Rst_n));

CounterData counteData(.Step(DataClk),
					.Rst_n(Rst_n), 
					.Reverse(CounterReverse), 
					.Set(DataSet), 
                    .Ready(DataReady),
					.In(RamOutCntrIn), 
					.Out(RamInCntrOut));

assign Ready = (NextApLineState == NONE) & DataReady & ApReady;

always @(negedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        LastApLineState <= NONE;
        NextApLineState <= NONE;
        ApCounterLock <= 1'b0;
    end
    else begin
        LastApLineState <= NextApLineState;
        case(LastApLineState)
            NONE: begin
                NextApLineState <= (ApCountAck & DataReady & ApReady )? 
                                        (ApCounterLock ? DATA_STORE : AP_COUNT) :
                                            DataCountAck ? 
                                                (ApCounterLock ? DATA_COUNT : DATA_LOAD) : 
                                                (DataWriteAck ? DATA_STORE : NONE );
            end
            DATA_LOAD: begin
                ApCounterLock <= 1'b1;
                NextApLineState <= DataCountAck & DataReady ? AP_COUNT : NONE;
            end
            DATA_COUNT: begin
                NextApLineState <= DataCountAck & DataReady ? DATA_COUNT : NONE;
            end
            DATA_STORE: begin
                ApCounterLock <= 1'b0;
                NextApLineState <= ApCountAck & ApReady ? AP_COUNT : NONE;
            end
            AP_COUNT: begin
                NextApLineState <= ApCountAck & ApReady ? AP_COUNT : NONE;            
            end
            default: begin
            NextApLineState <= NONE;
            end
        endcase
    end
end

endmodule