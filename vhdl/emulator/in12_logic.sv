module UpCounter #(
    parameter TOP = 4'b1001
)(
    input wire Tick,
    input wire Rst_n,
    output reg [4:0] Count
);

always @(posedge Tick, negedge Rst_n) begin
    Count <=  (!Rst_n) ? 4'b0 :
            (Count == TOP) ? 4'b0:
            Count + 1;
end

endmodule

module in12_cathodeToPinConverter(
    input wire [3:0] in,
    output reg[3:0] out
);

always @(*)
case (in)
    4'b0000: out = 4'b0001;
    4'b0001: out = 4'b0000;
    4'b0010: out = 4'b0010;
    4'b0011: out = 4'b0011;
    4'b0100: out = 4'b0110;
    4'b0101: out = 4'b1000;
    4'b0110: out = 4'b1001;
    4'b0111: out = 4'b0111;
    4'b1000: out = 4'b0101;
    4'b1001: out = 4'b0100;
    default: out = 4'b1010;
endcase

endmodule

module DekatronPC(
    output reg  [17:0] ipCounter,
    output reg [8:0] loopCounter,
    output reg [14:0] apCounter,
    output reg [8:0] dataCounter,
    input wire Clk,
    input wire Rst_n,
    input wire key_dpc_hard_rst,
    input wire key_dpc_soft_rst,
    input wire key_dpc_halt,
    input wire key_dpc_step,
    input wire key_dpc_run,
    output reg [2:0] DPC_currentState
);


reg [2:0] DPC_nextState;
parameter [2:0]
    DPC_HARD_RST = 3'b000,
    DPC_SOFT_RST = 3'b001,
    DPC_HALT = 3'b010,
    DPC_STEP = 3'b011,
    DPC_RUN = 3'b100;


always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        ipCounter <= 0654321;
        loopCounter <= 0321;
        apCounter <= 054321;
        dataCounter <= 0321;
    end
    else begin
        ipCounter <= ipCounter + 0111;
        loopCounter <= loopCounter + 0111;
        apCounter <= apCounter + 0111;
        dataCounter <= dataCounter + 0111;
    end

end


endmodule

module Impulse(
    input Clock,
    input Enable,
    input Rst_n,
    output wire Impulse
);

reg D_state;

assign Impulse = Enable & ~D_state;


always @(negedge Clock, negedge Rst_n) begin
    if (~Rst_n) begin
        D_state <= 1'b0;
    end
    else
    begin
        D_state <= Enable;
    end
end

endmodule