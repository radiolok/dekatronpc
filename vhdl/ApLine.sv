module ApLine(
    input wire Clk,
    input wire Rst_n,
    input wire ApCountEn,
    input wire ApReverse,
    output reg ApCounterLock,
    input wire RamCs,
    input wire Ram_WE_n,
    input wire DataCountEn,
    input wire DataReverse,
    input wire DataSet,
    input wire ExtDataWrite,
    input wire[9:0] DataIn,
    output wire[9:0] DataOut
);

wire[19:0] ApAddress;

wire ApClk = ApCountEn & Clk;

CounterAp AP(.Step(ApClk),
            .Reverse(ApReverse), 
            .Rst_n(Rst_n), 
            .Out(ApAddress));

wire [9:0] RamOutCntrIn;
wire [9:0] RamInCntrOut;

wire [9:0] RamDataIn = ExtDataWrite ? DataIn : RamInCntrOut;

RAM ram(.Address(ApAddress), 
        .In(RamDataIn), 
        .Out(RamOutCntrIn), 
        .CS(RamCs), 
        .WE_n(Ram_WE_n), 
        .Clk(Clk),
        .Rst_n(Rst_n));

wire DataClk = DataCountEn & Clk;

CounterData counteData(.Step(DataClk),
					.Reverse(DataReverse), 
					.Rst_n(Rst_n), 
					.Set(Set), 
					.In(RamOutCntrIn), 
					.Out(RamInCntrOut));

assign  DataOut = ApCounterLock ? RamInCntrOut : RamOutCntrIn;


always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) ApCounterLock <= 1'b0;
    else begin 
        if (~ApCounterLock & RamCs & Ram_WE_n & DataSet)
            ApCounterLock <= 1'b1;
        if ((ApCounterLock & RamCs & ~Ram_WE_n & ~DataSet) |(ExtDataWrite))
            ApCounterLock <= 1'b0;
    end
end
    

endmodule