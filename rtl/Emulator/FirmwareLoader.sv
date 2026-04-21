module FirmwareLoader #(
    parameter ROWS = 512,
    parameter FW_PATH = "../firmware.hex"
) (
    input wire Clk,
    input wire Rst_n,
    
    input wire Enable,
    
    input wire Ready,
    output wire Valid,

    output reg [INSN_WIDTH-1:0] InsnOut
);

wire Handshake;
assign Handshake = Valid & Ready;

reg [INSN_WIDTH-1:0] Mem [0:ROWS-1];

initial begin
    $readmemh(FW_PATH, Mem);
end

localparam ADDR_WIDTH = $clog2(ROWS);
reg [ADDR_WIDTH-1:0] Address;
reg [ADDR_WIDTH-1:0] NextAddress;
assign NextAddress = Address + 1'b1;

reg ValidInternal;
assign Valid = ValidInternal & Enable;

always_ff @(posedge Clk or negedge Rst_n) begin
    if (~Rst_n) begin
        ValidInternal <= 1'b0;
        Address <= '0;
        InsnOut <= '0;
    end
    else if (~Enable) begin
        ValidInternal <= 1'b1;
        Address <= '0;
        InsnOut <= Mem[1];
    end
    else begin
        if (Handshake) begin
            if (Address == ADDR_WIDTH'(ROWS - 1)) begin
                ValidInternal <= 1'b0;
            end
            else begin
                InsnOut <= Mem[NextAddress];
                Address <= NextAddress;
            end
        end
    end
end

endmodule
