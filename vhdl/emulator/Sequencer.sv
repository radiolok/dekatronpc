module Sequencer(
    input Clock_1us,
    input Enable,
    input Rst_n,
    output reg ms6205_write_addr,
    output reg ms6205_write_data,
    output reg in12_write_anode,
    output reg in12_write_cathode,
    output reg in12_clear,
    output reg keyboard_write,
    output reg keyboard_read,
    output reg keyboard_clear,
	output reg [2:0] state
);

parameter [2:0] 
		NONE = 0, 
		CATHODES = 1,
		ANODES = 2, 
		KEYBOARD_WR = 3, 
		MC_ADDR = 4, 
		MC_DATA = 5, 
		KEYBOARD_RD = 6, 
		STOP = 7;
reg [2:0] next_state;

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

assign in12_clear = Rst_n;
assign keyboard_clear = Rst_n;

always @(posedge Clock_1us, negedge Rst_n) begin
	if (!Rst_n) begin
		state <= NONE;
	 	in12_write_cathode <= 1'b0;
		in12_write_anode <= 1'b0;
		keyboard_write <= 1'b0;
		keyboard_read <= 1'b0;
		ms6205_write_addr <= 1'b0;
		ms6205_write_data <= 1'b0;
	end
	else begin
		state <= next_state;
		in12_write_cathode <= (state==CATHODES) & Enable;
        in12_write_anode <= (state==ANODES) & Enable;
        keyboard_write <= (state==KEYBOARD_WR) & Enable;
        keyboard_read <= (state==KEYBOARD_RD) & Enable;
        ms6205_write_addr <= ~((state==MC_ADDR) & Enable);
        ms6205_write_data <= ~((state==MC_DATA) & Enable);
	end
end

always @* begin
	case (state)
	NONE:
		next_state = (Enable)? KEYBOARD_RD : NONE;
	KEYBOARD_RD:
		next_state = (keyboard_read) ? CATHODES : KEYBOARD_RD;
	CATHODES:
		next_state = (in12_write_cathode) ? ANODES : CATHODES;
	ANODES:
		next_state = (in12_write_anode) ?  KEYBOARD_WR : ANODES;
	KEYBOARD_WR:
		next_state = (keyboard_write) ?  MC_ADDR : KEYBOARD_WR;
	MC_ADDR:
		next_state = (ms6205_write_addr) ? MC_DATA : MC_ADDR;
	MC_DATA:
		next_state =  (ms6205_write_data) ? STOP : MC_DATA;
	STOP:
		next_state = (Enable)? STOP : NONE;
	default:
		next_state = NONE;
	endcase
end


endmodule