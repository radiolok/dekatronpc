module tb;

reg Clk;
reg En;
reg Reverse;
reg Rst_n;
reg Set;
reg[9:0] In;

wire [3:0] DecOut;
wire [9:0] BinOut;

Octotron dek1(.Step(Clk),
            .En(En),
            .Reverse(Reverse),
            .Rst_n(Rst_n),
            .Set(Set),
            .In(In),
            .Out(BinOut)
            );



//convert binary to 8-4-2-1
BinToDbc bdc1(.In(BinOut), .Out(DecOut));

initial begin
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial
begin
	Rst_n <= 1'b0;
	Reverse <= 1'b0;
	Set <= 1'b0;
    En <= 1'b1;
	#1
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");
	#100;
	$display($time, "<< Simulation Complete >>");
	$stop;
end

always @(negedge Clk) begin
    $display($time, " Rst_n:%d, Set:%d, En:%d, Out: %d",  Rst_n, Set, En, DecOut);
end

endmodule