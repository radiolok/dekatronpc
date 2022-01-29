module Counter #(
    parameter DEKATRON_NUM = 6,
    parameter COUNT_DELAY = 3//delay in clockticks between Req and Rdy
)(	
	input wire Clk,
	input wire Rst_n,

    // All changes start on Request
    //If Set == 1, Out <= In
    //If Dec = 1, Out <= Out-1
    //Else, Out <= Out + 1
    input wire Request,
    input wire Dec,
    input wire Set,

    input wire [DEKATRON_NUM*3-1:0] In,

	output wire Ready,
	output reg [DEKATRON_NUM*3-1:0] Out
);

reg [COUNT_DELAY-1:0] delay_shifter;

/*==========================================================*/
/*FSM for counter. Result on output is guaranteed if Ready == 1*/

assign Ready = delay_shifter[0];

/*==========================================================*/

always @(posedge Clk, negedge Rst_n)
    begin
       if (~Rst_n) begin
           delay_shifter <= {{(COUNT_DELAY-1){1'b0}}, 1'b1};
           Out <= {(DEKATRON_NUM*3){1'b0}};           
       end
       else begin
           if (~(Ready & ~Request)) begin // Simulate internal logic delay.
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
           end
           if (Ready & Request) Out <= Set ? In : (Dec ? Out - 1 : Out + 1);
       end
    end


endmodule