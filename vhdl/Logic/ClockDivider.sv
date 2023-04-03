// fpga4student.com: FPGA projects, VHDL projects, Verilog projects
// Verilog project: Verilog code for clock divider on FPGA
// Top level Verilog code for clock divider on FPGA
module ClockDivider #(
    parameter DIVISOR = 28'd2,
    parameter DUTY_CYCLE=50 //percents
)(
    input wire Rst_n,
    input wire clock_in,
    output reg clock_out
    );

reg[27:0] counter=28'd0;
// The frequency of the output clk_out
//  = The frequency of the input clk_in divided by DIVISOR
// For example: Fclk_in = 50Mhz, if you want to get 1Hz signal to blink LEDs
// You will modify the DIVISOR parameter value to 28'd50.000.000
// Then the frequency of the output clk_out = 50Mhz/50.000.000 = 1Hz
always @(posedge clock_in, negedge Rst_n) begin
    if (~Rst_n) begin
        counter <= 28'b0;
        clock_out <= 1'b0;
    end
    else begin
        counter <= counter + 28'd1;
        if(counter>=(DIVISOR-1))
        counter <= 28'd0;
        clock_out <= (counter<((DIVISOR*DUTY_CYCLE)/100))? 1'b1: 1'b0;            
    end
end
endmodule
