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
reg [1:0] current_state;
reg [1:0] next_state;

assign Ready = current_state[0] & ~current_state[1];//READY

parameter[2:0] 
    NONE = 2'b00,
    READY = 2'b01,
    WAIT = 2'b10,
    REQUEST = 2'b11;

always @(*) begin
    case (current_state)
    NONE:
        next_state = READY;
    READY:
        if (Request) next_state = REQUEST;
    REQUEST:
        next_state = WAIT;
    WAIT:
        if (delay_shifter[0]) next_state = READY;
    endcase
end

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) begin
		current_state <= NONE;
	end
	else begin
		current_state <= next_state;
	end
end
/*==========================================================*/


always @(posedge Clk, negedge Rst_n)
    begin
       if (~Rst_n) begin
           delay_shifter <= {{(COUNT_DELAY-1){1'b0}}, 1'b1};
           Out <= {(DEKATRON_NUM*3){1'b0}};           
       end
       else begin
           if (current_state[1]) begin // REQUEST | WAIT
               delay_shifter <= {delay_shifter[0], delay_shifter[COUNT_DELAY-1:1]};
           end
           if (current_state[1] & current_state[0]) begin//REQUEST
               Out <= Set? In : Dec? Out - 1 : Out + 1;
           end
       end
    end


endmodule