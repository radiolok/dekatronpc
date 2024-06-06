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
	input 		          		FPGA_CLK_50,
	input 		          		FPGA_CLK2_50,
	input 		          		FPGA_CLK3_50,
	/* 3.3-V LVTTL */
	input				[1:0]			KEY,	
	output			    [7:0]			LED,
	input				[3:0]			SW,
    /* verilator lint_on UNUSEDSIGNAL */	

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

	output [7:0] emulData,

    output wire Clock_1s,
    output wire Clock_1ms,
    output wire Clock_1us,

    output wire Cout,
    output wire CinReq,

    output wire [7:0] stdout,

    input wire [7:0] stdin,
    
    output wire [3:0] io_address,
    output wire [1:0] io_enable_n,
    inout wire [7:0] io_data,

    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DPC_DataOut,
`ifdef EMULATOR
    output wire [31:0] IRET,

`endif

    input wire CioAcq,
    
    output wire [2:0] DPC_currentState
);

assign LED = 8'b0;

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
    assign IpAddress1[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:2*DEKATRON_WIDTH] = IpAddress[IP_DEKATRON_NUM*DEKATRON_WIDTH-1:2*DEKATRON_WIDTH];

    BCDCounter U_IpMS6205Counter(
        .Clk(Clk),
        .Rst_n(Rst_n),
        .count(IpAddress1[2*DEKATRON_WIDTH-1:0])
    );
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
    .Clk(Clk),
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
    .ipCounter(IpAddress),
`ifdef EMULATOR
    .ipCounter1(IpAddress1),
    .RomData1(RomData1),
`endif
    .loopCounter(LoopCount),
    .apCounter(ApAddress),
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


