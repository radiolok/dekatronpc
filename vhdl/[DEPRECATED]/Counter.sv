(* keep_hierarchy = "yes" *) module Counter #(
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

reg Busy;

assign Ready = 1'b1;
assign Buzy = 1'b0;

assign Zero = (Out == {(DEKATRON_NUM*DEKATRON_WIDTH){1'b0}});

always @(posedge Clk, negedge Rst_n)
    begin
       if (~Rst_n) begin
           Out <= {(DEKATRON_NUM*DEKATRON_WIDTH){1'b0}};
       end
       else begin
           Out <= Set ? In : (Dec ? Out - 1'b1 : Out + 1'b1);
       end
    end


endmodule