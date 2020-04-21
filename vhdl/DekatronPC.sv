module DekatronPC(
    input Clk,
    input Rst_n,
    output wire[15:0] Opcode
);

parameter SequencerWidth = 16;

wire [SequencerWidth-1:0] sequencerOut;

Sequencer #(.LENGTH(SequencerWidth)) 
                    sequencer(.Clk(Clk),
                    .Rst_n(Rst_n),
                    .Out(sequencerOut)
                    );


wire Count = sequencerOut[0];//First step is ever IP couner //TODO: check for cin;
wire Reverse = 1'b0;//not now
wire Load = sequencerOut[1];//Second step is ever load from ROM

NextOpcode nextOpcode(.Rst_n(Rst_n),
                .Count(Count),
                .Reverse(Reverse),
                .Load(Load),
                .Opcode(Opcode)
                );

endmodule