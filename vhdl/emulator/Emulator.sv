module Emulator (
	//////////// CLOCK //////////
	input 		          		FPGA_CLK_50,
	input 		          		FPGA_CLK2_50,
	input 		          		FPGA_CLK3_50,
	
	input [6:0] keyboard_data_in,

	input ms6205_ready,
	output ms6205_write_addr,
	output ms6205_write_data,
    output ms6205_marker,

	output in12_write_anode,
	output in12_write_cathode,
	output in12_clear,

	output keyboard_write,
	output keyboard_read,

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


wire  [17:0] ipCounter;
wire [8:0] loopCounter;
wire [14:0] apCounter;
wire [8:0] dataCounter;

wire Rst_n;

assign Rst_n = KEY[0];

wire [7:0] cathodeData;

assign cathodeData[7] = 1'b0;
assign cathodeData[3] = 1'b0;

assign LED[0] = Clock_1s;


`ifdef MODELSIM_MODE
    assign Clock_1us = FPGA_CLK_50;
`else
    Clock_divider #(.DIVISOR(28'd50)) clock_divider_us(
        .Rst_n(Rst_n),
        .clock_in(FPGA_CLK_50),
        .clock_out(Clock_1us)
    );
`endif

Clock_divider #(.DIVISOR(28'd1000)) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_1ms)
);

wire Clock_500ms;
Clock_divider #(.DIVISOR(28'd500)) clock_divider_500ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_500ms)
);


Clock_divider #(.DIVISOR(28'd1000)) clock_divider_s(
    .Rst_n(Rst_n),
	.clock_in(Clock_1ms),
	.clock_out(Clock_1s)
);


DekatronPC dekatronPC(
    .ipCounter(ipCounter),
    .loopCounter(loopCounter),
    .apCounter(apCounter),
    .dataCounter(dataCounter),
    .Clk(Clock_500ms),
    .Rst_n(Rst_n)
);

wire [4:0] anodeCount;

wire [2:0]cathodeLow;
wire [2:0] cathodeHigh;

in12_cathodeToPinConverter cathodeLowConvert
(
    .in(cathodeLow),
    .out(cathodeData[6:4])
);

in12_cathodeToPinConverter cathodeHighConvert
(
    .in(cathodeHigh),
    .out(cathodeData[2:0])
);

//This mux  compress IP and LOOP data into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(5)
)  muxCathode1
        (  .data({
            ipCounter,
            loopCounter}),
            .sel(anodeCount),
            .y(cathodeLow)
        );
    
//This mux  compress AP and DATA info into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(8), 
.SEL_WIDTH(5)
)  muxCathode2
        (  .data({
            apCounter,
            4'b0000,
            dataCounter}),
            .sel(anodeCount),
            .y(cathodeHigh)
        );

wire [9:0] anodeSel;

Impulse impulse(
	.Clock(Clock_1us),
	.Rst_n(Rst_n),
	.Enable(Clock_1ms),
	.Impulse(anodesClkTick)
);

//We do anodes inc only when we need it
UpCounter #(.TOP(4'b1001)) anodesCounter(
            .Tick(anodesClkTick),
            .Rst_n(Rst_n),
            .Count(anodeCount)
);

BdcToBin  bdcToBin(
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
        {8'b00000000, 
        8'b00000000, 
        ms6205_data,
        ms6205_addr, 
        anodeSel[7:0], 
        {4'b0000, anodeCount}, 
        cathodeData, 
        8'b00000000}),
    .sel(selectOutput),
    .y(emulData)
);

wire [39:0] keyboard_keysCurrentState;

Keyboard kb(
    .Rst_n(Rst_n),
    .Clk(Clock_1us),
    .kbCol(anodeSel),
    .kbRow(keyboard_data_in),
    .write(keyboard_write),
	.read(keyboard_read),
    .clear(keyboard_clear),
    .keysCurrentState(keyboard_keysCurrentState)
);

Ms6205 ms6205(
    .Rst_n(Rst_n),
    .Clk(Clock_1ms),
    .address(ms6205_addr),
    .data(ms6205_data),
    .write_addr(ms6205_write_addr),
    .write_data(ms6205_write_data),
    .marker(ms6205_marker),
    .ready(ms6205_ready),
    .key_ms6205_iram(keyboard_keysCurrentState[KEYBOARD_IRAM_KEY]),
    .key_ms6205_dram(keyboard_keysCurrentState[KEYBOARD_DRAM_KEY]),
    .key_ms6205_cin(keyboard_keysCurrentState[KEYBOARD_CIN_KEY]),
    .key_ms6205_cout(keyboard_keysCurrentState[KEYBOARD_COUT_KEY])
);

Sequencer sequencer(
	.Clock_1us(Clock_1us),
	.Enable(Clock_1ms),
	.Rst_n(Rst_n),
	.ms6205_write_addr(ms6205_write_addr),
	.ms6205_write_data(ms6205_write_data),
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

