module Emulator #(
    parameter DIVIDE_TO_1US = 28'd50,
    parameter DIVIDE_TO_1MS = 28'd1000,
    parameter DIVIDE_TO_4MS = 28'd3000,
    parameter DIVIDE_TO_1S = 28'd1000,
    parameter BOARDS = 16,
    parameter INSTALLED_BOARDS = 2
)(
	//////////// CLOCK //////////
	input 		          		FPGA_CLK_50,
	input 		          		FPGA_CLK2_50,
	input 		          		FPGA_CLK3_50,
	
	input [6:0] keyboard_data_in,

	input ms6205_ready,
	output ms6205_write_addr_n,
	output ms6205_write_data_n,
    output ms6205_marker,

	output in12_write_anode,
	output in12_write_cathode,
	output in12_clear,

	output keyboard_write,
	output keyboard_clear,

	output [7:0] emulData,

	//////////// KEY ////////////
	/* 3.3-V LVTTL */
	input				[1:0]			KEY,
	
	//////////// LED ////////////
	/* 3.3-V LVTTL */
	output			[7:0]			LED,
	
	//////////// SW ////////////
	/* 3.3-V LVTTL */
	input				[3:0]			SW,

    output wire Clock_1s,
    output wire Clock_1ms,
    output wire Clock_1us,

    output wire [3:0] io_address,
    output wire [1:0] io_enable_n,
    inout wire [7:0] io_data
);

`include "keyboard_keys.sv" 

wire  [17:0] ipCounter;
wire [8:0] loopCounter;
wire [14:0] apCounter;
wire [8:0] dataCounter;

wire [39:0] keyboard_keysCurrentState;

wire Rst_n;

wire hard_rst_key;

assign Rst_n = KEY[0];

assign LED[0] = Clock_1s;

wire [7:0] symbol;

Clock_divider #(.DIVISOR({DIVIDE_TO_1US})) clock_divider_us(
    .Rst_n(Rst_n),
    .clock_in(FPGA_CLK_50),
    .clock_out(Clock_1us)
);

Clock_divider #(
    .DIVISOR({DIVIDE_TO_1MS}),
    .DUTY_CYCLE(80)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_1ms)
);

Clock_divider #(
    .DIVISOR({DIVIDE_TO_1S})
) clock_divider_s(
    .Rst_n(Rst_n),
	.clock_in(Clock_1ms),
	.clock_out(Clock_1s)
);

wire [2:0] DPC_currentState;

wire [39:0] keyboard_keysCurrentState_added;

DekatronPC dekatronPC(
    .ipCounter(ipCounter),
    .loopCounter(loopCounter),
    .apCounter(apCounter),
    .dataCounter(dataCounter),
    .Clock_1ms(Clock_1ms),
    .symbol(symbol),
    .Rst_n(Rst_n),
    .keysCurrentState(keyboard_keysCurrentState_added),
    .DPC_currentState(DPC_currentState)
);


io_key_display_block #(
    .DIVIDE_TO_4MS(DIVIDE_TO_4MS)
)ioKeyDisplayBlock(
    .keyboard_data_in(keyboard_data_in),
    .ms6205_ready(ms6205_ready),
    .ms6205_write_addr_n(ms6205_write_addr_n),
    .ms6205_write_data_n(ms6205_write_data_n),
    .ms6205_marker(ms6205_marker),
    .in12_write_anode(in12_write_anode),
    .in12_write_cathode(in12_write_cathode),
    .in12_clear(in12_clear),
    .keyboard_write(keyboard_write),
    .keyboard_clear(keyboard_clear),
    .keyboard_keysCurrentState(keyboard_keysCurrentState),
    .emulData(emulData),
    .ipCounter(ipCounter),
    .loopCounter(loopCounter),
    .apCounter(apCounter),
    .dataCounter(dataCounter),
    .Clock_1s(Clock_1s),
    .Clock_1ms(Clock_1ms),
    .Clock_1us(Clock_1us),
    .Rst_n(Rst_n),
    .symbol(symbol),
    .DPC_currentState(DPC_currentState)
);

/*
yam430_core Yam430(
    .Clk(Clock_1us),
	.Rst_n(Rst_n)
);*/

wire [128:0] io_input_regs;
wire [128:0] io_output_regs;

wire Clock_10us;

Clock_divider #(
    .DIVISOR(10)
) clock_divider_10us(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_10us)
);

io_register_block #(
    .BOARDS(BOARDS),
    .INSTALLED_BOARDS(INSTALLED_BOARDS)
)IoRegisterBlock(
    .Clk(Clock_10us),
	.Rst_n(Rst_n),
    .io_address(io_address),
    .io_enable_n(io_enable_n),
    .io_data(io_data),
    .inputs(io_input_regs),
    .outputs(io_output_regs)
);


wire start_button = ~io_input_regs[0] | keyboard_keysCurrentState[KEYBOARD_RUN_KEY];
wire stop_button = ~io_input_regs[1] | keyboard_keysCurrentState[KEYBOARD_HALT_KEY];

assign LED[1] = start_button;
assign LED[2] = stop_button;

assign keyboard_keysCurrentState_added = {keyboard_keysCurrentState[39:29], 
                                    start_button, 
                                    keyboard_keysCurrentState[27], 
                                    stop_button, 
                                    keyboard_keysCurrentState[25:0]};

wire [3:0] digit;
wire[7:0] seg;

wire dp;



wire Clock_10ms;

Clock_divider #(
    .DIVISOR(5)
) clock_divider_10ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1ms),
	.clock_out(Clock_10ms)
);

reg [3:0] current_digit_shift;
reg [1:0] current_digit;

always @(posedge Clock_10ms, negedge Rst_n) begin
    if (~Rst_n) begin
        current_digit_shift <= 4'b0001;
        current_digit <= 2'b00;
    end
    else begin
        current_digit_shift <= {current_digit_shift[2:0], current_digit_shift[3]};
        current_digit <= current_digit + 2'b01;
    end
end


wire [7:0] output_ch0;
wire [7:0] output_ch1;

bn_mux_n_1_generate #(
.DATA_WIDTH(3), 
.SEL_WIDTH(2)
) muxOutput(
    .data(
        ipCounter[11:0]),//NONE
    .sel(current_digit),
    .y(digit)
);

segment7 segment7(
    .hex(digit),
    .seg(seg)
);

assign output_ch1 = {seg[1], seg[6], seg[2], seg[3], seg[4], seg[5], seg[0], 1'b0};
/*
bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(2)
) muxOutput(
    .data(
        io_input_regs[31:0]),//NONE
    .sel(output_ch1),
    .y(digit)
);*/

assign output_ch0 = {4'b0, current_digit_shift[0], current_digit_shift[1], current_digit_shift[3], current_digit_shift[2]};

assign io_output_regs = {112'b0, output_ch1, output_ch0};




endmodule


