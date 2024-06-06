module MS6205(
    input wire Clk,
    input wire Rst_n,
    input wire Clock_1ms,
    output reg ms6205_addr_acq,
	output reg ms6205_data_acq,
    input wire [7:0] symbol,
    input wire Cout,
    output reg CioAcq,
    output reg [7:0] address,
    output wire [7:0] data_n,
    input wire [INSN_WIDTH-1:0] RomData1,
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress,
    input wire  [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress1,
    input wire write_addr,
    input wire write_data,
    input wire ready,
    input wire [39:0] keysCurrentState,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire marker,    
    input wire [2:0] DPC_State
);

    /* verilator lint_off UNUSEDSIGNAL */
    wire Cin=1'b0;
    /* verilator lint_on UNUSEDSIGNAL */

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
/* verilator lint_on UNDRIVEN */
//reg [7:0] DRAM [0: MAX_POS-1];
reg [7:0] stdioAddr;

initial begin
    $readmemh("./Emulator/MSmemZero.hex", stdioRam);
end

always @(negedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        stdioAddr <= 8'h0;
    end
    else begin
        insnRam[ipAddress1[7:0]+6] <= RomData1;
        if ((Cout| Cin) & ~CioAcq) begin
            CioAcq <= 1'b1;
            stdioRam[stdioAddr] <= symbol;
            stdioAddr <= stdioAddr + 1;
        end
        if (~Cout & ~Cin & CioAcq) begin
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

always @(negedge Clock_1ms, negedge Rst_n) begin
    if (~Rst_n) begin
        ms6205Pos <= 8'h00;
        stdioData <= 8'h00;
        address <= 8'h00;
        ms6205_addr_acq <= 1'b1;
        ms6205_data_acq <= 1'b1;
    end
    else begin
        ms6205Pos <= ms6205Pos  + 8'h1;
        address <= ms6205Pos;
        if (ms6205Pos == MAX_POS -1) begin
            ms6205Pos <= 8'h0;
        end
        case (ms6205_currentView)
            (MS6205_IRAM): begin
                case (ms6205Pos[3:0])
                    (0): begin
                        stdioData <= 8'h20;// {4'b0, ipAddress1[19:16]} + 8'h30;
                    end
                    (1): begin
                        stdioData <= 8'h20;//{4'b0, ipAddress1[15:12]} + 8'h30;
                    end
                    (2): begin
                        stdioData <= 8'h20;// {4'b0, ipAddress1[11:8]} + 8'h30;
                    end
                    (3): begin
                        stdioData <= 8'h20;// {4'b0, ipAddress1[7:4]} + 8'h30;
                    end
                    (4): begin
                        stdioData <= 8'h20;//{4'b0, ipAddress1[3:0]} + 8'h30;
                    end
                    (5): begin
                        stdioData <= ":";
                    end
                    default: begin
                        stdioData <= OpcodeToSymbol({1'b1, insnRam[ms6205Pos]});
                    end
                endcase
            end
            default: begin
                stdioData <= stdioRam[ms6205Pos];
            end
        endcase
    end
end
endmodule
