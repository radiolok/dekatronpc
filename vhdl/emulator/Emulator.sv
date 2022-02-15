module Emulator #(
    parameter DIVIDE_TO_1US = 28'd50,
    parameter DIVIDE_TO_1MS = 28'd1000,
    parameter DIVIDE_TO_4MS = 28'd3000,
    parameter DIVIDE_TO_1S = 28'd1000
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
    output wire anodesClkTick
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

wire [7:0] cathodeData;

assign LED[0] = Clock_1s;

wire Clock_4ms;

wire [15:0] numericKey;
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
    .DIVISOR({DIVIDE_TO_4MS}),
    .DUTY_CYCLE(80)
) clock_divider_4ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_4ms)
);

Clock_divider #(
    .DIVISOR({DIVIDE_TO_1S})
) clock_divider_s(
    .Rst_n(Rst_n),
	.clock_in(Clock_1ms),
	.clock_out(Clock_1s)
);

wire [2:0] DPC_currentState;

DekatronPC dekatronPC(
    .ipCounter(ipCounter),
    .loopCounter(loopCounter),
    .apCounter(apCounter),
    .dataCounter(dataCounter),
    .Clock_1ms(Clock_1ms),
    .symbol(symbol),
    .Rst_n(Rst_n),
    .keysCurrentState(keyboard_keysCurrentState),
    .DPC_currentState(DPC_currentState)
);

wire [3:0] anodeCount;

wire [2:0]cathodeLow;
wire [2:0] cathodeHigh;

in12_cathodeToPinConverter cathodeLowConvert
(
    .in({1'b0, cathodeLow}),
    .out(cathodeData[7:4])
);

in12_cathodeToPinConverter cathodeHighConvert
(
    .in({1'b0,cathodeHigh}),
    .out(cathodeData[3:0])
);

//This mux  compress IP and LOOP data into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(3), 
.SEL_WIDTH(4)
)  muxCathode1
        (  .data({
            22'b0,
            ipCounter,
            loopCounter}),
            .sel(anodeCount),
            .y(cathodeHigh)
        );
    
//This mux  compress AP and DATA info into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(3), 
.SEL_WIDTH(4)
)  muxCathode2
        (  .data({
            22'b0,
            apCounter,
            3'b000,
            dataCounter}),
            .sel(anodeCount),
            .y(cathodeLow)
        );

wire [9:0] anodeSel;

Impulse impulse(
	.Clock(Clock_1us),
	.Rst_n(Rst_n),
	.Enable(Clock_4ms),
	.Impulse(anodesClkTick)
);

//We do anodes inc only when we need it
UpCounter #(.TOP(4'b1000)) anodesCounter(
            .Tick(anodesClkTick),
            .Rst_n(Rst_n),
            .Count(anodeCount)
);

BcdToBin  bcdToBin(
    .In(anodeCount),
    .Out(anodeSel)
);

wire [7:0] ms6205_addr;
wire [7:0] ms6205_data;

wire [2:0] selectOutput;

bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(3)
) muxOutput(
    .data(
        {8'b00000000, //STOP
        8'b00001001,  //KEYBOARD_RD + IN TURN OF ANODES
        ms6205_data,  //MC_DATA
        ms6205_addr, //MC_ADDR
        anodeSel[7:0], //KEYBOARD_WR
        {4'b0000, anodeCount}, //ANODES
        cathodeData, //CATHODES
        8'b00000000}),//NONE
    .sel(selectOutput),
    .y(emulData)
);

Keyboard kb(
    .Rst_n(Rst_n),
    .Clk(Clock_1us),
    .kbCol(anodeSel),
    .kbRow(keyboard_data_in),
    .write(keyboard_write),
	.read(keyboard_read),
    .symbol(symbol),
    .numericKey(numericKey),
    .clear(keyboard_clear),
    .keysCurrentState(keyboard_keysCurrentState)
);

wire ms6205_marker_en;

assign ms6205_marker = ms6205_marker_en & Clock_1s;

Ms6205 ms6205(
    .Rst_n(Rst_n),
    .Clock_1ms(Clock_1ms),
    .address(ms6205_addr),
    .data(ms6205_data),
    .ipAddress(ipCounter[7:0]),
    .symbol(symbol),
    .ms6205_addr_acq(ms6205_addr_acq),
	.ms6205_data_acq(ms6205_data_acq),
    .write_addr(ms6205_write_addr_n),
    .write_data(ms6205_write_data_n),
    .marker(ms6205_marker_en),
    .ready(ms6205_ready),
    .DPC_State(DPC_currentState),
    .keysCurrentState(keyboard_keysCurrentState)
);

Sequencer sequencer(
	.Clock_1us(Clock_1us),
	.Enable(Clock_1ms),
	.Rst_n(Rst_n),
    .ms6205_addr_acq(ms6205_addr_acq),
	.ms6205_data_acq(ms6205_data_acq),
	.ms6205_write_addr_n(ms6205_write_addr_n),
	.ms6205_write_data_n(ms6205_write_data_n),
	.in12_write_anode(in12_write_anode),
	.in12_write_cathode(in12_write_cathode),
	.in12_clear(in12_clear),
	.keyboard_write(keyboard_write),
	.keyboard_clear(keyboard_clear),
	.keyboard_read(keyboard_read),
    .state(selectOutput)
);
/*
yam430_core Yam430(
    .Clk(Clock_1us),
	.Rst_n(Rst_n)
);*/


endmodule

