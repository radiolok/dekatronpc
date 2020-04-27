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


wire OpcodeReady;
wire OpcodeAck;
wire [9:0] DataOut;
wire [9:0] DataIn;
wire        DataZero;
wire DataWriteAck;

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .DataZero(DataZero),
    .Opcode(Opcode),
    .OpcodeAck(OpcodeAck),
    .OpcodeReady(OpcodeReady)
);

ApLine APline(.Rst_n(Rst_n),
                .Clk(Clk),
                .DataOut(DataOut),
                .DataIn(DataIn),
                .DataWriteAck(DataWriteAck)
                );


ZeroDetector zeroDetector(.Data(DataOut),
                        .Zero(DataZero)
                );

ConsoleIn consoleIn(
                    .Clk(Clk),
                    .Rst_n(Rst_n),
                    .Data(DataIn),
                    .Ready(DataWriteAck)
                    );

ConsoleOut consoleOut(
                    .Clk(Clk),
                    .Rst_n(Rst_n),
                    .Data(DataOud)
                    );

endmodule