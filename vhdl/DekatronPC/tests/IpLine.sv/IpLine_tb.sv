module ip_line_tb #(
);

reg Clk;
reg Rst_n;
reg dataIsZeroed;
reg Request;

wire Ready;

wire [3:0] Insn;
IpLine  ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .dataIsZeroed(dataIsZeroed),
    .Request(Request),
    .Ready(Ready),
    .Insn(Insn)
);

initial begin
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial begin
    Rst_n <= 0;
    dataIsZeroed <= 1;
    #1  Rst_n <= 1;
    #40    
	$display($time, "<< Simulation Complete >>");
	$stop;
end

always @(posedge Clk, Rst_n) begin
    if (~Rst_n)
        Request <= 0;
    else
        Request <= Ready;
end

endmodule