module DekatronPC #(
    parameter IP_DEKATRON_NUM = 6,
    parameter LOOP_DEKATRON_NUM = 3,
    parameter AP_DEKATRON_NUM = 5,
    parameter DATA_DEKATRON_NUM = 3,    
    parameter DEKATRON_WIDTH = 4,
    parameter INSN_WIDTH = 4
)(
    input Clk,
    input hsClk,
    input Rst_n, 
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data
);

reg IpRequest;
wire IpLineReady;

wire [3:0] Insn;
reg InsnMode;

wire DataZero;
wire ApZero;

reg ApRequest = 1'b0;
reg DataRequest = 1'b0;

wire ApLineReady;

reg ApLineDec;

IpLine ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .dataIsZeroed(DataZero),
    .Request(IpRequest),
	.Ready(IpLineReady),
    .Address(IpAddress),
	.Insn(Insn)
);

ApLine  apLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .DataZero(DataZero),
    .ApZero(ApZero),
    .ApRequest(ApRequest),
    .DataRequest(DataRequest),
    .Dec(ApLineDec),
    .Ready(ApLineReady),
    .Address(ApAddress),
    .Data(Data)
);

parameter [0:0]
    INSN_DEBUG_MODE  = 1'b0,
    INSN_BRAINFUCK_MODE = 1'b1;

parameter [2:0]
    IDLE     =  4'b0001,
    FETCH     =  4'b0010,
    EXEC    =  4'b0100,
    HALT    =  4'b1000;

reg [3:0] currentState;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        IpRequest <= 1'b0;
        ApLineDec <= 1'b0;
        ApRequest <= 1'b0;
        DataRequest <= 1'b0;
        currentState <= IDLE;
        InsnMode <= INSN_BRAINFUCK_MODE;//FIX: Debug mode must be by default.
    end
    else begin
        case (currentState)
            IDLE: begin
                currentState <= FETCH;
                IpRequest <= 1'b1;
            end
            FETCH: begin
                IpRequest <= 1'b0;
                if (IpLineReady) begin
                    casex (Insn)
                        4'b0000: begin//NOP
                            currentState <= FETCH;
                            IpRequest <= 1'b1;
                        end
                        4'b0001: begin//HALT
                            currentState <= HALT;
                        end
                        4'b001x: begin
                            if (InsnMode == INSN_BRAINFUCK_MODE) begin
                                currentState <= EXEC;
                                DataRequest <= 1'b1;
                                ApRequest <= 1'b0;
                                ApLineDec <= Insn[0];
                            end
                        end
                        4'b010x: begin
                            if (InsnMode == INSN_BRAINFUCK_MODE) begin
                                currentState <= EXEC;
                                DataRequest <= 1'b0;
                                ApRequest <= 1'b1;
                                ApLineDec <= Insn[0];
                            end
                        end
                        4'b1000: begin
                            // synopsys translate_off
                            $display("COUT: %x", Data);
                            //Need to covert BCD to ASCII
                            // synopsys translate_on
                            currentState <= FETCH;
                            IpRequest <= 1'b1;
                        end
                        4'b1110: begin
                            InsnMode <= INSN_DEBUG_MODE;
                        end
                        4'b1111: begin
                            InsnMode <= INSN_BRAINFUCK_MODE;
                        end
                        default: begin
                            currentState <= FETCH;
                            IpRequest <= 1'b1;
                        end
                    endcase
                end
            end
            EXEC: begin
                DataRequest <= 1'b0;
                ApRequest <= 1'b0;
                if (ApLineReady) begin
                    currentState <= FETCH;
                    IpRequest <= 1'b1;
                end
            end
            HALT: begin
                // synopsys translate_off
                $finish;
                // synopsys translate_on
            end
            default: begin
                currentState <= IDLE;
            end
        endcase
    end

end
endmodule
