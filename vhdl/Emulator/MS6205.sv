module MS6205(
    input wire Rst_n,
    input wire Clock_1us,
    input wire Clock_1ms,
    output reg ms6205_addr_acq,
	output reg ms6205_data_acq,
    input wire [7:0] tx_data,
    input wire tx_vld,
    output reg [7:0] address,
    output wire [7:0] data_n,
    input wire [INSN_WIDTH-1:0] RomData1,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apData,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apData1,
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress,
    output reg  [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress1,
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apAddress,
    output reg  [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apAddress1,
    input wire write_addr,
    input wire write_data,
    input wire ready,
    input wire [39:0] keysCurrentState,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire marker,    
    input wire [2:0] DPC_State
);
reg CioAcq;

reg [2:0] ms6205_currentView;

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter MAX_POS = COLUMNS * ROWS;

parameter [2:0] 
    MS6205_RESTART = 3'b000,
    MS6205_IRAM = 3'b010,
    MS6205_DRAM = 3'b011,
    MS6205_CIO = 3'b101;

reg [2:0] ms6205_nextView;

assign marker = (ms6205_currentView == MS6205_IRAM) & (DPC_State == 2);

always_comb begin
    if (ms6205_currentView == MS6205_RESTART) begin
        ms6205_nextView = MS6205_IRAM;
    end
    else begin
        if (keysCurrentState[KEYBOARD_IRAM_KEY])
            ms6205_nextView = MS6205_IRAM;
        else if (keysCurrentState[KEYBOARD_DRAM_KEY])
            ms6205_nextView = MS6205_DRAM;
        else if (keysCurrentState[KEYBOARD_CIO_KEY] | CioAcq)
            ms6205_nextView = MS6205_CIO;
        else if (keysCurrentState[KEYBOARD_HARD_RST])
            ms6205_nextView = MS6205_RESTART;
        else
            ms6205_nextView = ms6205_currentView;
    end
end

always @(negedge Clock_1ms, negedge Rst_n) begin
    if (!Rst_n)
        ms6205_currentView <= MS6205_RESTART;
    else begin
        ms6205_currentView <= ms6205_nextView;
    end
end

//wire PressedKey = |symbol;

reg [7:0] stdioRam [0: MAX_POS-1];
/* verilator lint_off UNDRIVEN */
reg [3:0] insnRam [0: MAX_POS-1];

reg [11:0] dataRam [0: 9];
/* verilator lint_on UNDRIVEN */
//reg [7:0] DRAM [0: MAX_POS-1];
reg [7:0] stdioAddr;

initial begin
    $readmemh("../Emulator/MSmemZero.hex", stdioRam);
    $readmemh("../Emulator/MSmemZero.hex", insnRam);
end

always @(negedge Clock_1us, negedge Rst_n) begin
    if (~Rst_n) begin
        stdioAddr <= 8'h0;
        CioAcq <= 1'b0;
    end
    else begin
        insnRam[ipAddress1[7:0]+6] <= RomData1;
        dataRam[apAddress1[3:0]] <= (apAddress == apAddress1)? apData : apData1; 
        if ((tx_vld) & ~CioAcq) begin
            CioAcq <= 1'b1;
            stdioRam[stdioAddr] <= tx_data;
            stdioAddr <= stdioAddr + 1;
        end
        if (~tx_vld & CioAcq) begin
            if (ms6205_currentView == MS6205_CIO)
                CioAcq <= 1'b0;
        end
    end
end

reg [7:0] stdioData;
reg [7:0] ms6205Pos;
wire [7:0] data;

assign data_n = ~data;

assign data = stdioData;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] currentDataRam0 = dataRam[ms6205Pos[7:4]*2];
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] currentDataRam1 = dataRam[ms6205Pos[7:4]*2+1];

always @(negedge Clock_1ms, negedge Rst_n) begin
    if (~Rst_n) begin
        ms6205Pos <= 8'h00;
        stdioData <= 8'h00;
        address <= 8'h00;
        ms6205_addr_acq <= 1'b1;
        ms6205_data_acq <= 1'b1;
    end
    else begin
        ipAddress1[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:2*DEKATRON_WIDTH] <= ipAddress[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:2*DEKATRON_WIDTH];
        apAddress1[AP_DEKATRON_NUM*DEKATRON_WIDTH-1:1*DEKATRON_WIDTH] <= apAddress[AP_DEKATRON_NUM*DEKATRON_WIDTH-1:1*DEKATRON_WIDTH];
        ipAddress1[2*DEKATRON_WIDTH-1:0] <= ms6205Pos;
        apAddress1[1*DEKATRON_WIDTH-1:0] <= ms6205Pos[6:3];
        ms6205Pos <= ms6205Pos  + 8'h1;
        address <= ms6205Pos;
        if (ms6205Pos == MAX_POS -1) begin
            ms6205Pos <= 8'h0;
        end
        case (ms6205_currentView)
            (MS6205_IRAM): begin
                case (ms6205Pos[3:0])
                    (0): begin
                        stdioData <= {4'b0, ipAddress1[19:16]} + 8'h30;
                    end
                    (1): begin
                        stdioData <= {4'b0, ipAddress1[15:12]} + 8'h30;
                    end
                    (2): begin
                        stdioData <= {4'b0, ipAddress1[11:8]} + 8'h30;
                    end
                    (3): begin
                        stdioData <= {4'b0, ipAddress1[7:4]} + 8'h30;
                    end
                    (4): begin
                        stdioData <= 8'h30;
                    end
                    (5): begin
                        stdioData <= ":";
                    end
                    default: begin
                        stdioData <= OpcodeToSymbol({1'b1, insnRam[ms6205Pos]});
                    end
                endcase
            end
            (MS6205_DRAM): begin
                if (ms6205Pos < 80) begin
                    case (ms6205Pos[3:0])
                        (0): begin
                            stdioData <= {4'b0, apAddress1[19:16]} + 8'h30;
                        end
                        (1): begin
                            stdioData <= {4'b0, apAddress1[15:12]} + 8'h30;
                        end
                        (2): begin
                            stdioData <= {4'b0, apAddress1[11:8]} + 8'h30;
                        end
                        (3): begin
                            stdioData <= {4'b0, apAddress1[7:4]} + 8'h30;
                        end
                        (4): begin
                            stdioData <= {4'b0, ms6205Pos[7:4]} + 8'h30;
                        end
                        (5): begin
                            stdioData <= ":";
                        end
                        (7): begin
                            stdioData <= {4'b0, currentDataRam0[11:8]} + 8'h30;
                        end
                        (8): begin
                            stdioData <= {4'b0, currentDataRam0[7:4]} + 8'h30;
                        end
                        (9): begin
                            stdioData <= {4'b0, currentDataRam0[3:0]} + 8'h30;
                        end
                        (12): begin
                            stdioData <= {4'b0, currentDataRam1[11:8]} + 8'h30;
                        end
                        (13): begin
                            stdioData <= {4'b0, currentDataRam1[7:4]} + 8'h30;
                        end
                        (14): begin
                            stdioData <= {4'b0, currentDataRam1[3:0]} + 8'h30;
                        end
                        default: begin
                            stdioData <= " ";
                        end
                    endcase
                end else begin
                    stdioData <= " ";
                end
            end
            default: begin
                stdioData <= stdioRam[ms6205Pos];
            end
        endcase
    end
end
endmodule
