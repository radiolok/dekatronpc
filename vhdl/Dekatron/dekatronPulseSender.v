module DekatronPulseSender(
    //Each Step cause +1 or -1(if Reverse) or storing In value(if Set)
    input wire Clk,    
    input wire Rst_n,
	input wire En,
    input wire Reverse,//1 for reverse
    output wire PulseRight_n,
    output wire PulseLeft_n
);

reg [1:0] Pulses;

assign PulseRight_n = En ? Pulses[0] : 1'b1;
assign PulseLeft_n = En ? Pulses[1] : 1'b1;

parameter PULSE_FAIL = 2'b00;
parameter PULSE_RIGHT = 2'b10;
parameter PULSE_LEFT = 2'b01;
parameter PULSE_NONE = 2'b11;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        Pulses <= PULSE_NONE;
    end
    else begin
        if (En) begin
            case (Pulses)
                PULSE_FAIL: begin 
                    //Prohibited state!
                    Pulses <= PULSE_NONE;
                end
                PULSE_RIGHT: begin
                    Pulses <= Reverse ? PULSE_NONE : PULSE_LEFT;
                end
                PULSE_LEFT: begin
                    Pulses <= Reverse ? PULSE_RIGHT : PULSE_NONE;
                end
                PULSE_NONE: begin
                    Pulses <= Reverse ? PULSE_LEFT : PULSE_RIGHT;
                end
            endcase
        end
        else 
            Pulses <= PULSE_NONE;
            
    end
end
endmodule
