module KeyToSymbol(
    input wire [15:0] numericKey,
    input wire BFISA,
    output wire [7:0] symbol
);

assign symbol = OpcodeToSymbol({BFISA, BinaryToHex(numericKey)});


endmodule
