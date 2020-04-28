module ConsoleIn
    # (parameter DataSize = 10)
    (
    input wire Clk,
    input wire Rst_n,
    input wire Ack,
    output wire Ready,
    output wire[DataSize-1:0] Data
    );

assign Data = Rst_n ? 10'b0101010101 : {DataSize{1'bz}};

endmodule

module ConsoleOut
    # (parameter DataSize = 10)
    (
        input wire Clk,
        input wire Rst_n,
        output wire Write,
        input wire[DataSize-1:0] Data
    );

endmodule