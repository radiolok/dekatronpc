module KeyToSymbol(
    input wire [15:0] numericKey,
    output wire [7:0] symbol
);

assign symbol = OpcodeToSymbol(BinaryToHex(numericKey));


endmodule
