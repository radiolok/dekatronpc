module KeyboardOpcodeInput(
    input Clk,
    input Rst_n,
    
    input [7:0] Symbol,
    output reg [3:0] Opcode,
    
    input Ready,
    output reg Valid
);

wire hasSymbol;
assign hasSymbol = |Symbol;

reg hasSymbolReg;
wire symbolInputStart;
assign symbolInputStart = hasSymbol & ~hasSymbolReg;

always_ff @(posedge Clk or negedge Rst_n) begin
    if (~Rst_n) begin
        Valid <= 1'b0;
        Opcode <= 4'b0;
        hasSymbolReg <= 1'b0;
    end
    else begin
        hasSymbolReg <= hasSymbol;

        if (Valid) begin
            if (Ready) begin
                Valid <= 1'b0;
            end
        end
        else begin
            if (symbolInputStart) begin
                Valid <= 1'b1;
                Opcode <= {SymbolToOpcode(.symbol(Symbol), .isa(1'b0))}[3:0];
            end
        end
    end
end

endmodule
