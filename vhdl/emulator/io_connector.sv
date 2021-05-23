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

`ifdef enable_ADC
	//////////// ADC //////////
	/* 3.3-V LVTTL */
	output		          		ADC_CONVST,
	output		          		ADC_SCLK,
	output		          		ADC_SDI,
	input 		          		ADC_SDO,
`endif
	
`ifdef enable_ARDUINO
	//////////// ARDUINO ////////////
	/* 3.3-V LVTTL */
	inout					[15:0]	ARDUINO_IO,
	inout								ARDUINO_RESET_N,
`endif
	
`ifdef enable_GPIO0
	//////////// GPIO 0 ////////////
	/* 3.3-V LVTTL */
	inout				[35:0]		GPIO_0,
`endif

`ifdef enable_GPIO1	
	//////////// GPIO 1 ////////////
	/* 3.3-V LVTTL */
	inout				[35:0]		GPIO_1,
`endif

`ifdef enable_HPS
	//////////// HPS //////////
	/* 3.3-V LVTTL */
	inout 		          		HPS_CONV_USB_N,
	
	/* SSTL-15 Class I */
	output		    [14:0]		HPS_DDR3_ADDR,
	output		     [2:0]		HPS_DDR3_BA,
	output		          		HPS_DDR3_CAS_N,
	output		          		HPS_DDR3_CKE,
	output		          		HPS_DDR3_CS_N,
	output		     [3:0]		HPS_DDR3_DM,
	inout 		    [31:0]		HPS_DDR3_DQ,
	output		          		HPS_DDR3_ODT,
	output		          		HPS_DDR3_RAS_N,
	output		          		HPS_DDR3_RESET_N,
	input 		          		HPS_DDR3_RZQ,
	output		          		HPS_DDR3_WE_N,
	/* DIFFERENTIAL 1.5-V SSTL CLASS I */
	output		          		HPS_DDR3_CK_N,
	output		          		HPS_DDR3_CK_P,
	inout 		     [3:0]		HPS_DDR3_DQS_N,
	inout 		     [3:0]		HPS_DDR3_DQS_P,
	
	/* 3.3-V LVTTL */
	output		          		HPS_ENET_GTX_CLK,
	inout 		          		HPS_ENET_INT_N,
	output		          		HPS_ENET_MDC,
	inout 		          		HPS_ENET_MDIO,
	input 		          		HPS_ENET_RX_CLK,
	input 		     [3:0]		HPS_ENET_RX_DATA,
	input 		          		HPS_ENET_RX_DV,
	output		     [3:0]		HPS_ENET_TX_DATA,
	output		          		HPS_ENET_TX_EN,
	inout 		          		HPS_GSENSOR_INT,
	inout 		          		HPS_I2C0_SCLK,
	inout 		          		HPS_I2C0_SDAT,
	inout 		          		HPS_I2C1_SCLK,
	inout 		          		HPS_I2C1_SDAT,
	inout 		          		HPS_KEY,
	inout 		          		HPS_LED,
	inout 		          		HPS_LTC_GPIO,
	output		          		HPS_SD_CLK,
	inout 		          		HPS_SD_CMD,
	inout 		     [3:0]		HPS_SD_DATA,
	output		          		HPS_SPIM_CLK,
	input 		          		HPS_SPIM_MISO,
	output		          		HPS_SPIM_MOSI,
	inout 		          		HPS_SPIM_SS,
	input 		          		HPS_UART_RX,
	output		          		HPS_UART_TX,
	input 		          		HPS_USB_CLKOUT,
	inout 		     [7:0]		HPS_USB_DATA,
	input 		          		HPS_USB_DIR,
	input 		          		HPS_USB_NXT,
	output		          		HPS_USB_STP,
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


//assign data = GPIO_0[7:0];

//assign ms6205_write_addr = GPIO_0[8];
//assign ms6205_write_data = GPIO_0[9];
//assign ms6205_ready = GPIO_0[23];

//assign in12_write_anode = GPIO_0[10];
//assign in12_write_cathode = GPIO_0[11];
//assign in12_clear = GPIO_0[12];

//assign keyboard_write = GPIO_0[13];
//assign keyboard_clear = GPIO_0[14];
//assign keyboard_data_in = GPIO_0[22:16];

wire  [17:0] ipCounter;
wire [8:0] loopCounter;
wire [14:0] apCounter;
wire [8:0] dataCounter;
reg Clk;
reg Rst_n;

wire [7:0] cathodeData;

assign cathodeData[7] = 1'b0;
assign cathodeData[3] = 1'b0;


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

wire anodesClk;
reg anodesClkEn;

//We do anodes inc only when we need it
assign anodesClk = Clk & anodesClkEn;

UpCounter #(.TOP(4'b1001)) anodesCounter(
            .Clk(anodesClk),
            .Rst_n(Rst_n),
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
    .y(GPIO_0[7:0])
);

Keyboard kb(
    .kbCol(anodeSel),
    .kbRow(GPIO_0[22:16]),
    .write(GPIO_0[13]),
    .clear(GPIO_0[14])
);

Ms6205 ms6205(
    .address(ms6205_addr),
    .data(ms6205_data),
    .write_addr(GPIO_0[8]),
    .write_data(GPIO_0[9]),
    .ready(GPIO_0[23])

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



endmodule

