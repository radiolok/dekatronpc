module DekatronPulseSender(
    //Each Step cause +1 or -1(if Dec) or storing In value(if Set)
/* verilator lint_off UNUSEDSIGNAL */
    input wire Clk,    
/* verilator lint_on UNUSEDSIGNAL */
    input wire hsClk,    
    input wire Rst_n,    
    input wire En,
    input wire Dec,//1 for Dec
    output wire [1:0 ]PulsesOut
);

parameter HSCLK_DIV=10;
reg [HSCLK_DIV-1:0] pulseA;
reg [HSCLK_DIV-1:0] pulseB;

always @(posedge hsClk, Rst_n) begin
	if (~Rst_n) begin
	pulseA <= 10'b0011100000;		
	pulseB <= 10'b0000011100;		
	end
	else begin
	pulseA <= {pulseA[HSCLK_DIV-2:0], pulseA[HSCLK_DIV-1]};	
	pulseB <= {pulseB[HSCLK_DIV-2:0], pulseB[HSCLK_DIV-1]};	
	end


end

wire pA = pulseA[HSCLK_DIV-1];
wire pB = pulseB[HSCLK_DIV-1];

wire PulseRight = Dec? pB : pA;
wire PulseLeft = Dec? pA : pB;

assign PulsesOut = En? {PulseRight, PulseLeft} : 2'b00;

endmodule
