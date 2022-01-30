module DekatronPC(
    input Clk,
    input Rst_n,
    output wire[15:0] Opcode
);

wire OpcodeReady;
reg OpcodeAck;
wire   DataZero;

wire DataInReady;

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .DataZero(DataZero),
    .Opcode(Opcode),//Stable while OpcodeAck == 0 and OpcodeReady == 1
    .OpcodeAck(OpcodeAck),
    .OpcodeReady(OpcodeReady)
);

wire ApCountAck = OpcodeReady & (Opcode[3] | Opcode[4]);// ><
wire DataCountAck = OpcodeReady & (Opcode[1] | Opcode[2]);// +-
wire DataOutAck = OpcodeReady & Opcode[7]; // .;
wire DataInAck = OpcodeReady & Opcode[8];//,;
wire ApDataCounterReverce = OpcodeReady & (Opcode[2] | Opcode[4]);//- <
wire DataWriteAck = OpcodeReady & DataInReady & Opcode[8];
wire ApDataReady;

wire [9:0] DataOut;
wire [9:0] DataIn;

ApLine APline(
        .Clk(Clk),
        .Rst_n(Rst_n),
        .ApCountAck(ApCountAck),
        .DataCountAck(DataCountAck),
        .DataWriteAck(DataWriteAck),
        .CounterReverse(ApDataCounterReverce),
        .Ready(ApDataReady),
        .DataOut(DataOut),
        .DataIn(DataIn)
        );


ZeroDetector zeroDetector(.Data(DataOut),
                        .Zero(DataZero)
                );

ConsoleIn consoleIn(
                    .Clk(Clk),
                    .Rst_n(Rst_n),
                    .Data(DataIn),
                    .Ack(DataInAck),
                    .Ready(DataInReady)
                    );

ConsoleOut consoleOut(
                    .Clk(Clk),
                    .Rst_n(Rst_n),
                    .Data(DataOut),
                    .Write(DataOutAck)
                    );

always @(posedge Clk, negedge Rst_n) begin
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
                OpcodeAck <= (ApDataReady & DataInReady );
            end
        end

    end
end


endmodule