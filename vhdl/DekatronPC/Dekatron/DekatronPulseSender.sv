module DekatronPulseSender(
    //Each Step cause +1 or -1(if Dec) or storing In value(if Set)
    input wire Clk,    
    input wire Rst_n,
	input wire En,
    input wire Dec,//1 for Dec
    output wire [1:0 ]PulsesOut,
    output wire Ready
);

reg [1:0] Pulses;

parameter PULSE_FAIL = 2'b11;
parameter PULSE_RIGHT = 2'b01;
parameter PULSE_LEFT = 2'b10;
parameter PULSE_NONE = 2'b00;

assign PulsesOut = En ? Pulses : PULSE_NONE;

assign Ready = ~Pulses[0] & ~Pulses[1];

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Pulses <= PULSE_NONE;
    end
    else begin
        case (Pulses)
            PULSE_FAIL: begin 
                //Prohibited state!
                Pulses <= PULSE_NONE;
            end
            PULSE_RIGHT: begin
                Pulses <= Dec ? PULSE_NONE : PULSE_LEFT;
            end
            PULSE_LEFT: begin
                Pulses <= Dec ? PULSE_RIGHT : PULSE_NONE;
            end
            PULSE_NONE: begin
                Pulses <= Dec ? PULSE_LEFT : PULSE_RIGHT;
            end
        endcase
    end
end
endmodule
