module KeyboardOpcodeInput(
    input Clk,
    input Rst_n,

    input ReadEnable,
    
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

/* verilator lint_off UNUSEDSIGNAL */
wire [4:0] opcodeWide;
/* verilator lint_on UNUSEDSIGNAL */
assign opcodeWide = SymbolToOpcode(Symbol, 1'b0);

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
            if (ReadEnable & symbolInputStart) begin
                Valid <= 1'b1;
                Opcode <= opcodeWide[3:0];
            end
        end
    end
end

endmodule
