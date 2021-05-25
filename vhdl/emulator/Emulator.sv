//Group Enable Definitions
//This lists every pinout group
//Users can enable any group by uncommenting the corresponding line below:
//`define enable_ADC
//`define enable_ARDUINO
`define enable_GPIO0
`define enable_GPIO1
//`define enable_HPS

module Emulator (
	//////////// CLOCK //////////
	input 		          		FPGA_CLK_50,
	input 		          		FPGA_CLK2_50,
	input 		          		FPGA_CLK3_50,
	
	input [6:0] keyboard_data_in,

	input ms6205_ready,
	output ms6205_write_addr,
	output ms6205_write_data,

	output in12_write_anode,
	output in12_write_cathode,
	output in12_clear,

	output keyboard_write,
	output keyboard_read,
	output keyboard_clear,

	output [7:0] emulData,

`ifdef enable_GPIO1	
	//////////// GPIO 1 ////////////
	/* 3.3-V LVTTL */
	inout				[35:0]		GPIO_1,
`endif
	
	//////////// KEY ////////////
	/* 3.3-V LVTTL */
	input				[1:0]			KEY,
	
	//////////// LED ////////////
	/* 3.3-V LVTTL */
	output			[7:0]			LED,
	
	//////////// SW ////////////
	/* 3.3-V LVTTL */
	input				[3:0]			SW
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

wire Clock_1ms;
wire Clock_1us;

Clock_divider #(.DIVISOR(28'd50000)) clock_divider_ms(
	.clock_in(FPGA_CLK_50),
	.clock_out(Clock_1ms)
);

Clock_divider #(.DIVISOR(28'd50)) clock_divider_us(
	.clock_in(FPGA_CLK_50),
	.clock_out(Clock_1us)
);

DekatronPC dekatronPC(
    .ipCounter(ipCounter),
    .loopCounter(loopCounter),
    .apCounter(apCounter),
    .dataCounter(dataCounter)
);

//This mux  compress IP and LOOP data into 3-bit interface
mux_3b_9w muxCathode1
        (
            .d0(loopCounter[2:0]),
            .d1(loopCounter[5:3]),
            .d2(loopCounter[8:6]),
            .d3(ipCounter[2:0]),
            .d4(ipCounter[5:3]),
            .d5(ipCounter[8:6]),
            .d6(ipCounter[11:9]),
            .d7(ipCounter[14:12]),
            .d8(ipCounter[17:15]),
            .sel(anodeCount),
            .y(cathodeData[2:0])
        );
    
//This mux  compress AP and DATA info into 3-bit interface
mux_3b_9w muxCathode2
        (
            .d0(dataCounter[2:0]),
            .d1(dataCounter[5:3]),
            .d2(dataCounter[8:6]),
            .d3(4'b0000),
            .d4(apCounter[2:0]),
            .d5(apCounter[5:3]),
            .d6(apCounter[8:6]),
            .d7(apCounter[11:9]),
            .d8(apCounter[14:12]),
            .sel(anodeCount),
            .y(cathodeData[6:4])
        );

wire anodeSel;

wire anodesClkEn;

Impulse impulse(
	.Clock(Clock_1us),
	.Rst_n(Rst_n),
	.Enable(Clock_1ms),
	.Impulse(anodesClkEn)
);

//We do anodes inc only when we need it
UpCounter #(.TOP(4'b1001)) anodesCounter(
            .Clk(Clock_1us),
            .Rst_n(Rst_n),
			.Enable(anodesClkEn),
            .Count(anodeCount)
);

BdcToBin  bdcToBin(
    .In(anodeCount),
    .Out(anodeSel)
);

wire [7:0] ms6205_addr;
wire [7:0] ms6205_data;

mux_8b_5w muxOutput(
    .d0(cathodeData),
    .d1({4'b0000, anodeCount}),
    .d2(anodeSel),
    .d3(ms6205_addr),
    .d4(ms6205_data),
    .sel(selectOutput),
    .y(emulData)
);


Keyboard kb(
    .kbCol(anodeSel),
    .kbRow(keyboard_data_in),
    .write(keyboard_write),
	.read(keyboard_read),
    .clear(keyboard_clear)
);

Ms6205 ms6205(
    .address(ms6205_addr),
    .data(ms6205_data),
    .write_addr(ms6205_write_addr),
    .write_data(ms6205_write_data),
    .ready(ms6205_ready)

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
	.keyboard_read(keyboard_read)
);


endmodule

