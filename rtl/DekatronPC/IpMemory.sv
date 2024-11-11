module IpMemory #(
    parameter ROWS = 10**IP_DEKATRON_NUM
)(
    input wire Clk,
    input wire Rst_n,
    input wire Request,
    output wire Ready,
    input wire WE,
`ifdef EMULATOR
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address1,
    output wire [INSN_WIDTH-1:0] InsnOut1,
`endif
    input wire [INSN_WIDTH-1:0] InsnIn,
    output wire [INSN_WIDTH-1:0] InsnOut,
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address
);

`ifndef SYNTH
localparam ROM_DEKATRONS = 2;
localparam HIGH_ADDR = (10**(IP_DEKATRON_NUM-ROM_DEKATRONS)-1);
wire isBootloader = (Address[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:ROM_DEKATRONS*DEKATRON_WIDTH] == HIGH_ADDR);

wire [INSN_WIDTH-1: 0] RomOutWire;
reg [INSN_WIDTH-1: 0] RomOutReg;
reg [INSN_WIDTH-1: 0] RamOutReg;

localparam IP_RAM_BIN_BW = $clog2(ROWS-1);
wire [IP_RAM_BIN_BW-1:0] AddressBin;

BcdToBinEnc #(
    .DIGITS(IP_DEKATRON_NUM),
    .OUT_WIDTH(IP_RAM_BIN_BW)
) ApRAM_address_enc (
    .bcd(Address),
    .bin(AddressBin)
);


parameter [1:0]
    INIT      = 2'd0,
    READY     =  2'd1,
    BUSY      =  2'd2;

reg [1:0] state, next;

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) state <= INIT;
	else state <= next;
end

wire DataReady = 1; //Not used not, but for ROM delay modelling
always_comb begin
case (state)
    INIT: begin
        if (Request)
            next = BUSY;
        else
            next = INIT;
    end
    READY: begin
        if (Request)
            next = BUSY;
        else
            next = READY;
    end
    BUSY: begin
        if (DataReady)
            next = READY;
        else
            next = BUSY;
    end
    default:
        next = INIT;
endcase
end

assign Ready = ~Request & (state == READY);


assign InsnOut = (isBootloader) ? RomOutReg : RamOutReg;

reg [INSN_WIDTH-1:0] Mem [0:ROWS-1];
initial begin
    $readmemh("../firmware.hex", Mem);
end

bootloader #(
    .portSize(ROM_DEKATRONS*DEKATRON_WIDTH)
    )storage(
        .Address(Address[ROM_DEKATRONS*DEKATRON_WIDTH-1:0]),
        .Data(RomOutWire));

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
      RamOutReg <= {INSN_WIDTH{1'b0}};
      RomOutReg <= {(INSN_WIDTH){1'b0}};
    end
    else if (WE) Mem[AddressBin] <= InsnIn;
      else begin
        RamOutReg <= Mem[AddressBin];
        RomOutReg <= RomOutWire;
    end
end

`ifdef EMULATOR
    wire [IP_RAM_BIN_BW-1:0] Address1Bin;
    BcdToBinEnc #(
        .DIGITS(IP_DEKATRON_NUM),
        .OUT_WIDTH(IP_RAM_BIN_BW)
    ) ApRAM1_address_enc (
        .bcd(Address1),
        .bin(Address1Bin)
    );
    wire [INSN_WIDTH-1: 0] RomOutWire1;
    reg [INSN_WIDTH-1: 0] RomOutReg1;
    reg [INSN_WIDTH-1: 0] RamOutReg1;
    assign InsnOut1 = (isBootloader) ? RomOutReg1 : RamOutReg1;

    bootloader #(
        .portSize(ROM_DEKATRONS*DEKATRON_WIDTH)
        )storage1(
            .Address(Address1[ROM_DEKATRONS*DEKATRON_WIDTH-1:0]),
            .Data(RomOutWire1));

    always @(posedge Clk, negedge Rst_n) begin
        if (~Rst_n) begin
            RamOutReg1 <= {INSN_WIDTH{1'b0}};
            RomOutReg1 <= {(INSN_WIDTH){1'b0}};
        end
        else begin 
            RamOutReg1 <= Mem[Address1Bin];
            RomOutReg1 <= RomOutWire1;
        end
    end
`endif
`endif

endmodule
