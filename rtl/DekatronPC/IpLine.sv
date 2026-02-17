module IpLine (
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,
    input wire HaltRq,

    input wire dataIsZeroed,
    input wire key_next_app_i,
    input wire Request,
    output wire Ready,
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,

    output reg RomRequest,
    input wire RomReady,
    input wire [INSN_WIDTH-1:0] RomData,

    output reg[INSN_WIDTH-1:0] Insn
);

reg cnt_ip_request;
reg cnt_ip_dec;
wire cnt_ip_ready;

reg [3:0] AppNum;
reg prevApp;
assign IpAddress[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH] = AppNum;
always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        AppNum <= '0;
        prevApp <= '0;
    end else begin
        if (key_next_app_i) begin
            if (~prevApp) begin
                AppNum <= (AppNum < 9) ?  AppNum + 4'b1 : '0;
                prevApp <= 1'b1;
            end
        end
        else begin
            prevApp <= 1'b0;
        end
    end
end

DekatronCounter  #(
            .D_NUM(IP_DEKATRON_NUM-1),
		    .WRITE(1'b0)
            )IP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(cnt_ip_request),
                .Dec(cnt_ip_dec),
                .Set(1'b0),
                .SetZero(1'b0),
                .In({((IP_DEKATRON_NUM-1)*DEKATRON_WIDTH){1'b0}}),
                .Ready(cnt_ip_ready),
                .Out(IpAddress[(IP_DEKATRON_NUM-1)*DEKATRON_WIDTH-1:0]),
                /* verilator lint_off PINCONNECTEMPTY */
                .Zero()
                /* verilator lint_on PINCONNECTEMPTY */
            );

//This two highligh loop insn on the ROM output to control loopLookup
wire LoopInsnOpenInternal;
wire LoopInsnCloseInternal;

InsnLoopDetector insnLoopDetectorInternal(
    .Insn(RomData),
    .LoopOpen(LoopInsnOpenInternal),
    .LoopClose(LoopInsnCloseInternal)
);

//This two highligh loop insn on the output to begin loopLookup
wire LoopInsnOpen;
wire LoopInsnClose;

InsnLoopDetector insnLoopDetector(
    .Insn(Insn),
    .LoopOpen(LoopInsnOpen),
    .LoopClose(LoopInsnClose)
);

reg cnt_loop_request;
reg cnt_loop_dec;
wire Loop_Zero;
wire cnt_loop_ready;

`ifdef EMULATOR
    parameter LOOP_READ = 1'b1;
`else
    parameter LOOP_READ = 1'b0;
`endif

DekatronCounter  #(
            .D_NUM(LOOP_DEKATRON_NUM),
            .READ(LOOP_READ),
		    .WRITE(1'b0)
            )Loop_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(cnt_loop_request),
                .Dec(cnt_loop_dec),
                .Set(1'b0),
                .SetZero(1'b0),
                .In({(LOOP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                /* verilator lint_off PINCONNECTEMPTY */
                .Ready(cnt_loop_ready),
                .Out(LoopCount),
                /* verilator lint_on PINCONNECTEMPTY */
                .Zero(Loop_Zero)
            );

assign Ready = ((state == IDLE) | (state == READY))
                & cnt_loop_ready;//READY | IDLE

wire cnt_ip_back = (LoopInsnClose & ~dataIsZeroed); //backward direction for ']' & nonZero

parameter [2:0]
    IDLE      =  3'd0,
    IP_COUNT  =  3'd1,
    ROM_READ  =  3'd2,
    LOOP_COUNT = 3'd3,
    READY     =  3'd4,
    HALT      =  3'd7;

reg [2:0] state;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Insn <= {(INSN_WIDTH){1'b0}};
        cnt_ip_dec <= 1'b0;
        cnt_ip_request <= 1'b0;
        cnt_loop_request <= 1'b0;
        cnt_loop_dec <= 1'b0;
        RomRequest <= 1'b0;
        state <= IDLE;
    end
    else begin
        case (state)
            IDLE:
                if (HaltRq) state <= HALT;
                else if (Request) begin
                    if (RomReady) begin
                        RomRequest <= 1'b0;
                        cnt_ip_dec <= cnt_ip_back; //backward direction for ']' & nonZero
                        cnt_ip_request <= 1'b1;
                        if ((LoopInsnOpen & dataIsZeroed) |
                            (LoopInsnClose & ~dataIsZeroed)) begin
                            //Let's run loopLookup
                            cnt_loop_dec <= 1'b0;
                            cnt_loop_request <= 1'b1;
                            state <= LOOP_COUNT;
                        end
                        else
                            state <= IP_COUNT;
                    end
                    else begin//Only for IP=0
                        state <= ROM_READ;
                        RomRequest <= 1'b1;
                    end
                end
            IP_COUNT: begin
                if (cnt_ip_request & cnt_ip_ready) begin
                    cnt_ip_request <= 1'b0;
                    state <= ROM_READ;
                    RomRequest <= 1'b1;
                end
            end
            ROM_READ: begin
                    if (RomRequest & RomReady) begin
                        RomRequest <= 1'b0;
                        if (Loop_Zero) begin
                            state <= READY;
                        end
                        else begin
                            if (LoopInsnOpenInternal | LoopInsnCloseInternal) begin
                                cnt_loop_dec <= ((cnt_ip_back & LoopInsnOpenInternal)|
                                            (~cnt_ip_back & LoopInsnCloseInternal));
                                cnt_loop_request <= 1'b1;
                                state <= LOOP_COUNT;
                            end
                            else begin
                                state <= IP_COUNT;
                                cnt_ip_dec <= cnt_ip_back; //backward direction for ']' & nonZero
                                cnt_ip_request <= 1'b1;
                            end
                        end
                    end
                end
            LOOP_COUNT: begin
                if (cnt_loop_request & cnt_loop_ready) begin
                    cnt_loop_request <= 1'b0;
                    if ((LoopInsnOpenInternal | LoopInsnCloseInternal) & ~Loop_Zero) begin
                        cnt_ip_dec <= cnt_ip_back & ~Loop_Zero; //backward direction for ']' & nonZero
                        cnt_ip_request <= 1'b1;
                    end
                    state <= IP_COUNT;
                end
            end
            READY: begin
                Insn <= RomData;
                if (~Request) begin
                    state <= IDLE;
                end
            end
            HALT: begin
                if (HaltRq)
                    state <= HALT;
                else
                    state <= IDLE;
            end
            default:
                state <= IDLE;
        endcase
    end
end

endmodule
