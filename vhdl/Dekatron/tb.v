module tb;

reg Clk;
reg En;
reg Reverse;
reg Rst_n;
reg Set;
reg[9:0] In;

wire [3:0] DecOut;
wire [9:0] BinOut;

wire PulseRight_n;
wire PulseLeft_n;

wire Ready;

DekatronPulseSender dekatronPulseSender(.Clk(Clk),
                                        .En(En),
                                        .Rst_n(Rst_n),
                                        .Reverse(Reverse),
                                        .PulseRight_n(PulseRight_n),
                                        .PulseLeft_n(PulseLeft_n));

DekatronBulb dek1(
            .PulseRight_n(PulseRight_n),
            .PulseLeft_n(PulseLeft_n),
            .Rst_n(Rst_n),
            .Set(Set),
            .In(In),
            .Out(BinOut),
            .Ready(Ready)
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
    #20
    Reverse <= 1'b1;
	#41
    Reverse <= 1'b0;
	#41
    In <= 10'b0001000000;
    Set <= 1'b1;
    En <= 1'b0;
    #2
    Set <= 1'b0;
    En <= 1'b1;
    #20
	$display($time, "<< Simulation Complete >>");
	$stop;
end

always @(negedge Clk) begin
    $display($time, " Rst_n:%d, Set:%d, En:%d, PulseRight:%d, PulseLeft:%d, Out: %d",  Rst_n, Set, En, PulseRight_n, PulseLeft_n, DecOut);
end

endmodule