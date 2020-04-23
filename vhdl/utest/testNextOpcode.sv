`timescale 1 us / 1 ns
module testNextOpcode();

//Inputs to DUT are reg type
	reg Clk = 1'b0;
	reg Rst_n = 1'b0;
	reg Reverse = 1'b0;
	wire[15:0] Opcode;
	

parameter SequencerWidth = 4;

wire [SequencerWidth-1:0] sequencerOut;

Sequencer #(.LENGTH(SequencerWidth)) 
                    sequencer(.Clk(Clk),
                    .Rst_n(Rst_n),
                    .Out(sequencerOut)
                    );


wire Load = Rst_n & sequencerOut[0];//Second step is ever load from ROM
wire Count = Rst_n & sequencerOut[1];//Last step is ever IP couner //TODO: check for cin;

NextOpcode nextOpcode(.Rst_n(Rst_n),
                .Count(Count),
                .Reverse(Reverse),
                .Load(Load),
                .Opcode(Opcode)
                );

initial begin
Clk = 1'b0;
forever #1 Clk = ~Clk;
end


//Initial Block

initial
begin
	#3
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");
	
	#400;
	$display($time, "<< Simulation Complete >>");
	$stop;
end


always @(negedge Load)
	if (Rst_n)
		$display($time, "Addr: %d Opcode: %d ", nextOpcode.IpAddress, nextOpcode.Insn);

endmodule
