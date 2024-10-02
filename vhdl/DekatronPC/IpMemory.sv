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

localparam IP_RAM_BIN_BW = $clog2(ROWS/10-1);
wire [IP_RAM_BIN_BW-1:0] AddressBin;

BcdToBinEnc #(
    .DIGITS(IP_DEKATRON_NUM-1),
    .OUT_WIDTH(IP_RAM_BIN_BW)
) ApRAM_address_enc (
    .bcd(Address[(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH-1:0]),
    .bin(AddressBin)
);

wire [3:0] mem_bank = Address[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH];

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

reg [INSN_WIDTH-1:0] Mem0 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem1 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem2 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem3 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem4 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem5 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem6 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem7 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem8 [0:ROWS/10-1];
// reg [INSN_WIDTH-1:0] Mem9 [0:ROWS/10-1];
initial begin
    $readmemh("../firmware.hex", Mem0);
    // $readmemh("../firmware.hex", Mem1);
    // $readmemh("../firmware.hex", Mem2);
    // $readmemh("../firmware.hex", Mem3);
    // $readmemh("../firmware.hex", Mem4);
    // $readmemh("../firmware.hex", Mem5);
    // $readmemh("../firmware.hex", Mem6);
    // $readmemh("../firmware.hex", Mem7);
    // $readmemh("../firmware.hex", Mem8);
    // $readmemh("../firmware.hex", Mem9);        
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
    else if (WE) Mem0[AddressBin] <= InsnIn;
      else begin
        case(mem_bank)
            4'h0: begin
                RamOutReg <= Mem0[AddressBin];
            end
            // 4'h1: begin
            //     RamOutReg <= Mem1[AddressBin];
            // end
            // 4'h2: begin
            //     RamOutReg <= Mem2[AddressBin];
            // end
            // 4'h3: begin
            //     RamOutReg <= Mem3[AddressBin];
            // end
            // 4'h4: begin
            //     RamOutReg <= Mem4[AddressBin];
            // end
            // 4'h5: begin
            //     RamOutReg <= Mem5[AddressBin];
            // end
            // 4'h6: begin
            //     RamOutReg <= Mem6[AddressBin];
            // end
            // 4'h7: begin
            //     RamOutReg <= Mem7[AddressBin];
            // end
            // 4'h8: begin
            //     RamOutReg <= Mem8[AddressBin];
            // end
            // 4'h9: begin
            //     RamOutReg <= Mem9[AddressBin];
            // end
            default: begin
                RamOutReg <= Mem0[AddressBin];
            end
        endcase
        RomOutReg <= RomOutWire;
    end
end

`ifdef EMULATOR
    wire [IP_RAM_BIN_BW-1:0] Address1Bin;
    BcdToBinEnc #(
        .DIGITS(IP_DEKATRON_NUM-1),
        .OUT_WIDTH(IP_RAM_BIN_BW)
    ) ApRAM1_address_enc (
        .bcd(Address1[(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH-1:0]),
        .bin(Address1Bin)
    );
    wire [3:0] mem_bank_1 = Address1[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH];
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
            case(mem_bank_1)
            4'h0: begin
                RamOutReg1 <= Mem0[Address1Bin];
            end
            // 4'h1: begin
            //     RamOutReg1 <= Mem1[Address1Bin];
            // end
            // 4'h2: begin
            //     RamOutReg1 <= Mem2[Address1Bin];
            // end
            // 4'h3: begin
            //     RamOutReg1 <= Mem3[Address1Bin];
            // end
            // 4'h4: begin
            //     RamOutReg1 <= Mem4[Address1Bin];
            // end
            // 4'h5: begin
            //     RamOutReg1 <= Mem5[Address1Bin];
            // end
            // 4'h6: begin
            //     RamOutReg1 <= Mem6[Address1Bin];
            // end
            // 4'h7: begin
            //     RamOutReg1 <= Mem7[Address1Bin];
            // end
            // 4'h8: begin
            //     RamOutReg1 <= Mem8[Address1Bin];
            // end
            // 4'h9: begin
            //     RamOutReg1 <= Mem9[Address1Bin];
            // end
            default: begin
                RamOutReg1 <= Mem0[Address1Bin];
            end
        endcase
            RomOutReg1 <= RomOutWire1;
        end
    end
`endif
`endif

endmodule
