module IpMemory(
    input wire Clk,
    input wire Rst_n,
`ifdef EMULATOR
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address1,
    output wire [INSN_WIDTH-1:0] InsnOut1,
`endif
    input wire [INSN_WIDTH-1:0] InsnIn,
    output wire [INSN_WIDTH-1:0] InsnOut,
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address
);

localparam ROM_DEKATRONS = 2;
wire isBootloader = (Address[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:ROM_DEKATRONS*DEKATRON_WIDTH] == 16'h9999);

wire [INSN_WIDTH-1: 0] RomOutWire;
reg [INSN_WIDTH-1: 0] RomOutReg;
wire [INSN_WIDTH-1: 0] RamOut;

assign InsnOut = (isBootloader) ? RomOutReg : RamOut;

`ifdef EMULATOR
    wire [INSN_WIDTH-1: 0] RomOutWire1;
    reg [INSN_WIDTH-1: 0] RomOutReg1;
    wire [INSN_WIDTH-1: 0] RamOut1;
    assign InsnOut1 = (isBootloader) ? RomOutReg1 : RamOut1;
`endif

wire RomRequest = isBootloader & Request;
wire RamRequest = ~isBootloader & Request;

wire RomReady;
wire RamReady;

assign Ready = RomReady & RamReady;

RAM #(
    .ROWS(25'h1000000),
    .ADDR_WIDTH(IP_DEKATRON_NUM*DEKATRON_WIDTH),
    .DATA_WIDTH(INSN_WIDTH)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(Address),
    .In(InsnIn),
    .Out(RamOut),
`ifdef EMULATOR
    .Address1(Address1),
    .Out1(RamOut1),
`endif
    .WE(RamWE),
    .CS(RamCS)
);

// synopsys translate_off
bootloader #(
    .portSize(ROM_DEKATRONS*DEKATRON_WIDTH)
    )storage(
        .Address(Address[ROM_DEKATRONS*DEKATRON_WIDTH-1:0]),
        .Data(RomOutWire));
// synopsys translate_on

always @(posedge Clk, negedge Rst_n)
    if (~Rst_n) begin
        RomOutReg <= {(DATA_WIDTH){1'b0}};
    end
    else begin
        if (state == BUSY)
            RomOutReg <= RomOutWire;
    end

`ifdef EMULATOR
    // synopsys translate_off
    bootloader #(
        .portSize(ROM_DEKATRONS*DEKATRON_WIDTH)
        )storage1(
            .Address(Address1[ROM_DEKATRONS*DEKATRON_WIDTH-1:0]),
            .Data(RomOutWire1));
    // synopsys translate_on

    always @(negedge Clk, negedge Rst_n)
        if (~Rst_n) begin
            RomOutReg1 <= {(DATA_WIDTH){1'b0}};
        end
        else begin
            if (state == BUSY)
                RomOutReg1 <= RomOutWire1;
        end
`endif

endmodule
