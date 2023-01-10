module FourCounters(
    input wire Rst_n,
	input wire Clk,

	//highSpeed Clock to emulate delay of dekatron circuits. Clk is hsClk/10
	input wire hsClk,

	// All changes start on Request
    //If Set == 1, Out <= In
    //If Dec = 1, Out <= Out-1
    //Else, Out <= Out + 1
	input wire RequestIP,
    input wire DecIP,
    input wire SetIP,
    output wire ReadyIP,
    output wire ZeroIP,

    input wire RequestAP,
    input wire DecAP,
    output wire ReadyAP,
    output wire ZeroAP,

    input wire RequestLoop,
    input wire DecLoop,
    output wire ReadyLoop,
    output wire ZeroLoop,

    input wire RequestData,
    input wire DecData,
    input wire SetData,
    output wire ReadyData,
    output wire ZeroData,

    input wire [3*4-1:0] InData,

	output wire [6*4-1:0] OutIP,
    output wire [5*4-1:0] OutAP,
    output wire [3*4-1:0] OutData,

);

Counter #(.D_NUM(6)) ip(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .Request(RequestIP),
    .Dec(DecIP),
    .Ready(ReadyIP),
    .Zero(ZeroIP),
    .Out(OutIP)
);

Counter #(.D_NUM(5)) ap(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .Request(RequestAP),
    .Dec(DecAP),
    .Ready(ReadyAP),
    .Zero(ZeroAP),
    .Out(OutAP)
);

Counter #(.D_NUM(3)) data(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .Request(RequestData),
    .Dec(DecData),
    .Ready(ReadyData),
    .Zero(ZeroData),
    .In(InData),
    .Out(OutData)
);

Counter #(.D_NUM(3)) loop(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .Request(RequestLoop),
    .Dec(DecLoop),
    .Ready(ReadyLoop),
    .Zero(ZeroLoop)
);

endmodule