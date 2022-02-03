module Counter #(
    parameter DEKATRON_NUM = 6,
    parameter DEKATRON_WIDTH = 3,
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

    input wire [DEKATRON_NUM*DEKATRON_WIDTH-1:0] In,

	output wire Ready,
    output wire Zero,
	output reg [DEKATRON_NUM*DEKATRON_WIDTH-1:0] Out
);

reg [COUNT_DELAY-1:0] delay_shifter;
reg Busy;

assign Ready = ~Request & delay_shifter[0];
assign Zero = (Out == {(DEKATRON_NUM*DEKATRON_WIDTH){1'b0}});

always @(posedge Clk, negedge Rst_n)
    begin
       if (~Rst_n) begin
           delay_shifter <= {{(COUNT_DELAY-1){1'b0}}, 1'b1};
           Out <= {(DEKATRON_NUM*DEKATRON_WIDTH){1'b0}};
           Busy <= 1'b0;
       end
       else begin
           if (Busy) begin // Simulate internal logic delay.
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
               Busy <= ~delay_shifter[0];
           end
           if (~Busy & Request) begin
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
               Out <= Set ? In : (Dec ? Out - 1'b1 : Out + 1'b1);
               Busy <= 1'b1;
           end
       end
    end


endmodule