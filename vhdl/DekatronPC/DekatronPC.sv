module DekatronPC(
    input Clk,
    input Rst_n
);

reg IpLineRequest;
wire IpLineReady;

wire   DataZero;

wire [3:0] Insn;

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .dataIsZeroed(DataZero),
    .Request(IpLineRequest),
	 .Ready(IpLineReady),
	 .Insn(Insn),
);




endmodule