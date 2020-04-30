`define LOOP_TEST

module TestIpLine();

//Inputs to DUT are reg type
reg[3:0] Clk;

reg Rst_n;

wire[15:0] Opcode;
wire OpcodeReady;
reg OpcodeAck;
reg   DataZero;

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk[0]),
    .DataZero(DataZero),
    .Opcode(Opcode),//Stable while OpcodeAck == 0 and OpcodeReady == 1
    .OpcodeAck(OpcodeAck),
    .OpcodeReady(OpcodeReady)
);

initial begin
    Clk = 1'b0;
    forever #1 Clk = Clk + 1;
end
//Initial Block

initial
begin
	Rst_n <= 1'b0;
	DataZero <= 1'b0;
	OpcodeAck <= 1'b0;
	#3
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");
	#400;
	$display($time, "<< Simulation Complete >>");
	$stop;
end

always @(posedge Clk[3], negedge Rst_n) begin
    if (~Rst_n) begin
        OpcodeAck <=1'b1;
    end
    else begin
        if (OpcodeReady & OpcodeAck) 
            OpcodeAck <= 1'b0;
        if (OpcodeReady) begin
            if (OpcodeAck) 
                OpcodeAck <= 1'b0;
            else begin
                OpcodeAck <= (OpcodeReady);
            end
        end

    end
end


endmodule