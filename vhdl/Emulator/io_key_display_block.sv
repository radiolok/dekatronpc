
module io_key_display_block #(
    parameter DIVIDE_TO_4MS = 28'd3000
)(
    input wire Rst_n,

    input [6:0] keyboard_data_in,

	input ms6205_ready,
	output ms6205_write_addr_n,
	output ms6205_write_data_n,
    output ms6205_marker,

	output in12_write_anode,
	output in12_write_cathode,
	output in12_clear_n,

	output keyboard_write,
	output keyboard_clear,
    output wire [39:0] keyboard_keysCurrentState,

	output [7:0] emulData,
    input wire [2:0] DPC_currentState,

    output wire [7:0] symbol,

    input wire  [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipCounter,
    input wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] loopCounter,
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apCounter,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] dataCounter,

    input wire Clock_1s,
    input wire Clock_1ms,
    input wire Clock_1us
);

wire [3:0] anodeCount;

wire [3:0]cathodeLow;
wire [3:0] cathodeHigh;

wire anodesClkTick;

wire [7:0] cathodeData;

In12CathodeToPin cathodeLowConvert
(
    .in(cathodeLow),
    .out(cathodeData[7:4])
);

In12CathodeToPin cathodeHighConvert
(
    .in(cathodeHigh),
    .out(cathodeData[3:0])
);

//This mux  compress IP and LOOP data into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(4), 
.SEL_WIDTH(4)
)  muxCathode1
        (  .data({
            28'b0,
            ipCounter,
            loopCounter}),
            .sel(anodeCount),
            .y(cathodeHigh)
        );
    
//This mux  compress AP and DATA info into 3-bit interface
bn_mux_n_1_generate #(
.DATA_WIDTH(4), 
.SEL_WIDTH(4)
)  muxCathode2
        (  .data({
            28'b0,
            apCounter,
            4'b0,
            dataCounter}),
            .sel(anodeCount),
            .y(cathodeLow)
        );

wire Clock_4ms;
ClockDivider #(
    .DIVISOR({DIVIDE_TO_4MS}),
    .DUTY_CYCLE(80)
) clock_divider_4ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_4ms)
);

Impulse impulse(
	.Clk(Clock_1us),
	.Rst_n(Rst_n),
	.En(Clock_4ms),
	.Impulse(anodesClkTick)
);

//We do anodes inc only when we need it

UpCounter #(.TOP(4'b1010)) anodesCounter(
            .Tick(anodesClkTick),
            .Rst_n(Rst_n),
            .Count(anodeCount)
);

UpCounter #(.TOP(4'b1000)) kbRowCounter(
            .Tick(anodesClkTick),
            .Rst_n(Rst_n),
            .Count(kbRowCount)
);

/* verilator lint_off UNUSEDSIGNAL */
wire [9:0] kbColSel;
/* verilator lint_on UNUSEDSIGNAL */

BcdToBin  bcdToBin(
    .In(kbRowCount),
    .Out(kbColSel)
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
        kbColSel[7:0], //KEYBOARD_WR
        {4'b0000, anodeCount}, //ANODES
        cathodeData, //CATHODES
        8'b00000000}),//NONE
    .sel(selectOutput),
    .y(emulData)
);

wire keyboard_read;

/* verilator lint_off UNUSEDSIGNAL */
wire [15:0] numericKey;
/* verilator lint_on UNUSEDSIGNAL */

Keyboard kb(
    .Rst_n(Rst_n),
    .Clk(Clock_1us),
    .kbCol(kbColSel[7:0]),
    .kbRow(keyboard_data_in),
    .write(keyboard_write),
	.read(keyboard_read),
    .symbol(symbol),
    .numericKey(numericKey),
    .clear(keyboard_clear),
    .keysCurrentState(keyboard_keysCurrentState)
);

wire ms6205_marker_en;
wire ms6205_addr_acq;
wire ms6205_data_acq;

assign ms6205_marker = ms6205_marker_en & Clock_1s;

MS6205 ms6205(
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
	.in12_clear_n(in12_clear_n),
	.keyboard_write(keyboard_write),
	.keyboard_clear(keyboard_clear),
	.keyboard_read(keyboard_read),
    .state(selectOutput)
);

endmodule
