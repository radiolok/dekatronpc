module Sequencer(
    input Clock_1us,
    input Enable,
    input Rst_n,
	input wire ms6205_addr_acq,
	input wire ms6205_data_acq,
    output wire ms6205_write_addr_n,
    output wire ms6205_write_data_n,
    output reg in12_write_anode,
    output reg in12_write_cathode,
    output reg in12_clear_n,
    output reg keyboard_write,
    output reg keyboard_read,
    output reg keyboard_clear,
	output wire [2:0] state
);

reg ms6205_write_addr;
reg ms6205_write_data;

wire ms6205_write_addr_imp;
wire ms6205_write_data_imp;

assign ms6205_write_data_n = ~ms6205_write_data_imp;
assign ms6205_write_addr_n = ~ms6205_write_addr_imp;

Impulse impulse_addr(
	.Clk(Clock_1us),
	.Rst_n(Rst_n),
	.En(ms6205_write_addr),
	.Impulse(ms6205_write_addr_imp)
);

Impulse impulse_data(
	.Clk(Clock_1us),
	.Rst_n(Rst_n),
	.En(ms6205_write_data),
	.Impulse(ms6205_write_data_imp)
);

//Now, we need to do next job if ack signal:
/*
T+0:
Rise busy signal
T+1:
Anode counter +1
Cathode selector set on the output
T+2:
Cathodes Write toggle up - K155TM8 will work with Clock rising edge
T+3:
cathodes write toggle down
anode selector set to the output
T+4:
Anodes write signal rize
T+5:
Anodes write signal release
Busy signal release
*/

assign in12_clear_n = Rst_n;
assign keyboard_clear = Rst_n;

parameter [2:0] 
		NONE = 0, 
		CATHODES = 1,
		ANODES = 2, 
		KEYBOARD_WR = 3, 
		MC_ADDR = 4, 
		MC_DATA = 5, 
		KEYBOARD_RD = 6, 
		STOP = 7;
reg [2:0] current_state;
reg [2:0] next_state;

assign state = current_state;

always @(*) begin
	case (state)
	NONE:
		next_state = (Enable)? CATHODES : NONE;
	CATHODES:
		next_state = (in12_write_cathode) ? ANODES : CATHODES;
	ANODES:
		next_state = (in12_write_anode) ?  KEYBOARD_WR : ANODES;
	KEYBOARD_WR:
		if (~keyboard_write)
			next_state = KEYBOARD_WR;
		else begin
			if (ms6205_addr_acq) 
				next_state = MC_ADDR;
			else if (ms6205_data_acq)
				next_state = MC_DATA;
			else 
				next_state = STOP;
		end
	MC_ADDR:
		if (~ms6205_write_addr) 
			next_state = MC_ADDR;
		else 
			next_state = (ms6205_data_acq) ? MC_DATA : STOP;
	MC_DATA:
		next_state =  (ms6205_write_data) ? STOP : MC_DATA;
	STOP:
		next_state = (Enable)? STOP : KEYBOARD_RD;
	KEYBOARD_RD:
		next_state = (keyboard_read) ? NONE : KEYBOARD_RD;
	endcase
end

always @(posedge Clock_1us, negedge Rst_n) begin
	if (~Rst_n) begin
		current_state <= NONE;
	end
	else begin
		current_state <= next_state;
	end
end

always @(posedge Clock_1us, negedge Rst_n) begin
	if (!Rst_n) begin
	 	in12_write_cathode <= 1'b0;
		in12_write_anode <= 1'b0;
		keyboard_write <= 1'b0;
		keyboard_read <= 1'b0;
		ms6205_write_addr <= 1'b0;
		ms6205_write_data <= 1'b0;
	end
	else begin
		in12_write_cathode <= (current_state==CATHODES) & Enable;
        in12_write_anode <= ((current_state==ANODES) & Enable);// | ((current_state == KEYBOARD_RD) & ~Enable);
        keyboard_write <= (current_state==KEYBOARD_WR) & Enable;
        keyboard_read <= (current_state==KEYBOARD_RD) & ~Enable;
        ms6205_write_addr <= ((current_state==MC_ADDR) & Enable);
        ms6205_write_data <= ((current_state==MC_DATA) & Enable);
	end
end

endmodule
