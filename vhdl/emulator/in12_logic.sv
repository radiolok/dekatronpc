module UpCounter #(
parameter TOP = 4'b1001
)(
    input wire Clk,
    input wire Rst_n,
    input wire Enable,
    output reg [4:0] Count
);

always @(posedge Clk, negedge Rst_n) begin
    Count <=  (!Rst_n) ? 4'b0 :
            (Count == TOP) ? 4'b0:
            (Enable)? Count + 1 : Count;
end

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
    input wire key_dpc_run
);

output reg [2:0] DPC_currentState;
reg [2:0] DPC_nextState;
parameter [2:0]
    DPC_HARD_RST = 3'b000,
    DPC_SOFT_RST = 3'b001,
    DPC_HALT = 3'b010,
    DPC_STEP = 3'b011,
    DPC_RUN = 3'b100;


always @(*)
    case ()

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        ipCounter <= 0;
        loopCounter <= 0;
        apCounter <= 0;
        dataCounter <= 0;
    end
    else begin
        ipCounter <= ipCounter + 1;
        loopCounter <= loopCounter + 1;
        apCounter <= apCounter + 1;
        dataCounter <= dataCounter + 1;
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

always @(posedge Clock, negedge Rst_n) begin
    if (~Rst_n)
        D_state <= 1'b0;
    else
        D_state <= Enable;
end

endmodule