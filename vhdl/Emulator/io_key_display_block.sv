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

    input wire [7:0] tx_data,
    input wire tx_vld,

    input wire  [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress,
    output wire  [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ipAddress1,
    input wire [INSN_WIDTH-1:0] RomData1,    
    output wire  [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apAddress1,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apData1,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apData,
    input wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] loopCounter,
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] apAddress,

    input wire Clock_1s,
    input wire Clock_1ms,
    input wire Clock_1us
);

wire [3:0] anodeCount;

reg [3:0]cathodeLow;
reg [3:0] cathodeHigh;

wire [7:0] cathodeData;

assign cathodeData = {In12CathodeToPin(cathodeLow), In12CathodeToPin(cathodeHigh)};

wire [3:0] inIPHigh [0:9];
generate 
    genvar idx;
    for (idx = 0; idx < 9; idx = idx + 1) begin: IP_HIGH
        if (idx < IP_DEKATRON_NUM) begin: IP_EXIST
            assign inIPHigh[idx] = ipAddress[(idx+1)*4-1:idx*4];
        end
        else begin: IP_NOX_EXIST
            assign inIPHigh[idx] = 4'b0;
        end
    end
endgenerate

always_comb begin
    case(anodeCount)
        4'd0: begin
            cathodeHigh = loopCounter[3:0];
            cathodeLow = apData[3:0];
        end
        4'd1: begin
            cathodeHigh = loopCounter[7:4];
            cathodeLow = apData[7:4];
        end
        4'd2: begin
            cathodeHigh = loopCounter[11:8];
            cathodeLow = apData[11:8];
        end
        4'd3: begin
            cathodeHigh = inIPHigh[0];
            cathodeLow = 4'd0;
        end
        4'd4: begin
            cathodeHigh = inIPHigh[1];
            cathodeLow = apAddress[3:0];
        end
        4'd5: begin
            cathodeHigh = inIPHigh[2];
            cathodeLow = apAddress[7:4];
        end
        4'd6: begin
            cathodeHigh = inIPHigh[3];
            cathodeLow = apAddress[7:4];
        end
        4'd7: begin
            cathodeHigh = inIPHigh[4];
            cathodeLow = apAddress[11:8];
        end
        4'd8: begin
            cathodeHigh = inIPHigh[5];
            cathodeLow = apAddress[15:12];
        end
        default: begin
            cathodeHigh = 4'b0;
            cathodeLow = 4'b0;
        end
    endcase
end

wire Clock_4ms;
ClockDivider #(
    .DIVISOR({DIVIDE_TO_4MS}),
    .DUTY_CYCLE(80)
) clock_divider_4ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_4ms)
);

//We do anodes inc only when we need it

UpCounter #(.TOP(4'b1010)) anodesCounter(
            .Tick(Clock_4ms),
            .Rst_n(Rst_n),
            .Count(anodeCount)
);

wire [3:0] kbRowCount;
UpCounter #(.TOP(4'b1000)) kbRowCounter(
            .Tick(Clock_4ms),
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
wire [7:0] symbol;
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

assign ms6205_marker = ms6205_marker_en & Clock_1s;

MS6205 ms6205(
    .Rst_n(Rst_n),
    .Clock_1us(Clock_1us),
    .Clock_1ms(Clock_1ms),
    .address(ms6205_addr),
    .data_n(ms6205_data),
    .ipAddress(ipAddress),
    .ipAddress1(ipAddress1),
    .apAddress(apAddress),
    .apAddress1(apAddress1),
    .apData1(apData1),
    .apData(apData),
    .RomData1(RomData1),
    .tx_data(tx_data),
    .tx_vld_i(tx_vld),
    .write_addr(ms6205_write_addr_n),
    .write_data(ms6205_write_data_n),
    .marker(ms6205_marker_en),
    .ready(ms6205_ready),
    .DPC_State(DPC_currentState),
    .tx_switch_view_i(1'b0),
    .keysCurrentState(keyboard_keysCurrentState)
);

Sequencer sequencer(
	.Clock_1us(Clock_1us),
	.Enable(Clock_1ms),
	.Rst_n(Rst_n),
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
