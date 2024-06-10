module Emulator #(
    parameter DIVIDE_TO_1US = 28'd50,
    parameter DIVIDE_TO_1MS = 28'd1000,
    parameter DIVIDE_TO_4MS = 28'd3000,
    parameter DIVIDE_TO_1S = 28'd1000,
    parameter BOARDS = 16,
    parameter INSTALLED_BOARDS = 2
)(
    /* verilator lint_off UNUSEDSIGNAL */
	//////////// CLOCK //////////
	input 		          		FPGA_CLK_50,//V11
	input 		          		FPGA_CLK2_50,//Y13
	input 		          		FPGA_CLK3_50,//E11
	/* 3.3-V LVTTL */
	
	/*
	KEY0 - AH17
	KEY1 - AH16
	*/
	input				[1:0]			KEY,
	/* verilator lint_off UNDRIVEN */
    output			[7:0]			LED,
    /* verilator lint_on UNDRIVEN */
	/*
	SW0 - L10
	SW1 - L9
	SW2 - H6
	SW3 - H5
	*/
	input				[3:0]			SW,
    /* verilator lint_on UNUSEDSIGNAL */	

	 /*
	 D0 - AH3
	 D1 - AH2
	 D2 - AF4
	 D3 - AG6
	 D4 - AF5
	 D5 - AE4
	 D6 - T13
	 */
	input [6:0] keyboard_data_in,

	input ms6205_ready,//T11
	output ms6205_write_addr_n,//Y5
	output ms6205_write_data_n,//U11
   output ms6205_marker,//AG5

	output in12_write_anode,//T8
	output in12_write_cathode,//T12
	output in12_clear_n,//AH5

	output keyboard_write,//AH6
	output keyboard_clear,//AH4

	/*
	D0 - V12
	D1 - AF7
	D2 - W12
	D3 - AF8
	D4 - Y8
	D5 - AB4
	D6 - W8
	D7 - Y4
	*/
	output [7:0] emulData,

    output wire Clock_1s, //AF18 GPIO1.24
    output wire Clock_1ms, //AG23 GPIO1.22
    output wire Clock_1us, //AF25 GPIO1.20

    output wire Cout,
    output wire CinReq,

    output wire [7:0] stdout,

    input wire [7:0] stdin,
    
	 /*
	 A0 - AA18
	 A1 - AC22
	 A2 - AD23
	 A3 - AE23
	 */
    output wire [3:0] io_address,
    /*
	 EN1 - AG21
	 EN2 - AH18
	 */
	 output wire [1:0] io_enable_n,
	 /*
	 D0 - AE20
	 D1 - AD19
	 D2 - AD20
	 D3 - AE24
	 D4 - AH22
	 D5 - AF22
	 D6 - AH21
	 D7 - AH19
	 */
    inout wire [7:0] io_data,

    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DPC_DataOut,
    output wire [31:0] IRET,

    input wire CioAcq,
    
    output wire [2:0] DPC_currentState
);

assign LED[0] = Rst_n;
assign LED[1] =  Clock_1s;
assign LED[2] = Clock_1ms;

wire CoutAcq;

/* verilator lint_off UNUSEDSIGNAL */
wire [39:0] keysCurrentState;
/* verilator lint_on UNUSEDSIGNAL */

wire keyHalt = keysCurrentState[KEYBOARD_HALT_KEY];
wire keyRun = keysCurrentState[KEYBOARD_RUN_KEY];
wire keyStep = keysCurrentState[KEYBOARD_STEP_KEY];

wire Rst_n = KEY[0];

wire hsClk;
/* verilator lint_off UNUSEDSIGNAL */
wire [INSN_WIDTH - 1:0] Insn;
wire SoftRst_n = Rst_n & ~keysCurrentState[KEYBOARD_SOFT_RST_KEY];
wire HardRst_n = Rst_n & ~keysCurrentState[KEYBOARD_HARD_RST];
/* verilator lint_on UNUSEDSIGNAL */

generate
    if (DIVIDE_TO_1US == 1) begin
        assign Clock_1us = FPGA_CLK_50;
    end
    else begin
    ClockDivider #(.DIVISOR({DIVIDE_TO_1US})) clock_divider_us(
        .Rst_n(Rst_n),
        .clock_in(FPGA_CLK_50),
        .clock_out(Clock_1us)
    );
    end
endgenerate

ClockDivider #(
    .DIVISOR(8'd5),
    .DUTY_CYCLE(50)
) clock_divider_hsClk(
    .Rst_n(Rst_n),
	.clock_in(FPGA_CLK_50),
	.clock_out(hsClk)
);

wire Clk;

ClockDivider #(
    .DIVISOR(10)
) clock_divider_Clk(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);

ClockDivider #(
    .DIVISOR({DIVIDE_TO_1MS}),
    .DUTY_CYCLE(80)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(Clock_1us),
	.clock_out(Clock_1ms)
);

ClockDivider #(
    .DIVISOR({DIVIDE_TO_1S})
) clock_divider_s(
    .Rst_n(Rst_n),
	.clock_in(Clock_1ms),
	.clock_out(Clock_1s)
);

wire EchoMode = 1'b1;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DPC_DataIn;

assign stdout = BcdToAscii(DPC_DataOut);

assign DPC_DataIn = AsciiToBcd(stdin);

wire Acq = CioAcq | CoutAcq;
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress1;
/* verilator lint_on UNDRIVEN */
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1;
/* verilator lint_on UNUSEDSIGNAL */

`ifdef EMULATOR
    wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress1;
    wire [INSN_WIDTH-1:0] RomData1;
`endif

DekatronPC dekatronPC(
    .IpAddress(IpAddress),
    .ApAddress(ApAddress),
    .Data(DPC_DataOut),
    .LoopCount(LoopCount),
    .hsClk(hsClk),
    .Clk(Clk),
    .Rst_n(HardRst_n),
    .Halt(keyHalt),
    .Run(keyRun),
    .Cout(Cout),
    .InsnIn(4'b0),
    .EchoMode(EchoMode),
    .DataCin(DPC_DataIn),
    .CioAcq(Acq),
    .CinReq(CinReq),
    .Step(keyStep),
`ifdef EMULATOR
    .IRET(IRET),
    .IpAddress1(IpAddress1),
    .ApAddress1(ApAddress1),
    .ApData1(ApData1),
    .RomData1(RomData1),
`endif
    .state(DPC_currentState),
    .Insn(Insn)
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
    .in12_clear_n(in12_clear_n),
    .keyboard_write(keyboard_write),
    .keyboard_clear(keyboard_clear),
    .keyboard_keysCurrentState(keysCurrentState),
    .emulData(emulData),
    .ipAddress(IpAddress),
`ifdef EMULATOR
    .ipAddress1(IpAddress1),
    .RomData1(RomData1),
    .apAddress1(ApAddress1),
    .apData1(ApData1),
    .apData(DPC_DataOut),
`endif
    .loopCounter(LoopCount),
    .apAddress(ApAddress),
    .dataCounter(DPC_DataOut),
    .Clock_1s(Clock_1s),
    .Clock_1ms(Clock_1ms),
    .Clock_1us(Clock_1us),
    .Rst_n(Rst_n),
    .stdout(stdout),
    .Cout(Cout),
    .CioAcq(CoutAcq),
    .DPC_currentState(DPC_currentState)
);

/* verilator lint_off UNUSEDSIGNAL */
wire [127:0] io_input_regs;
/* verilator lint_on UNUSEDSIGNAL */

wire [127:0] io_output_regs = 128'b0;

wire Clock_10us;

ClockDivider #(
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


endmodule


