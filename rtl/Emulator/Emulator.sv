module Emulator #(
    parameter DIVIDE_TO_01US = 28'd5,
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

    input rx,//Y15
    output tx,//AA15

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

    output wire Clock_1Hz, //AF18 GPIO1.24
    output wire Clock_1KHz, //AG23 GPIO1.22
    output wire Clock_10KHz,
    output wire Clock_1MHz, //AF25 GPIO1.20

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

`ifdef VERILATOR
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress,
    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress,
    output wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd,
`endif

    output wire [2:0] DPC_currentState
);

assign LED[0] = Rst_n;
assign LED[1] = Clock_1Hz;
assign LED[2] = Clock_1KHz;

`ifndef VERILATOR
    wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress;
    wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress;
    wire [LOOP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] LoopCount;
    wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd;
`endif

/* verilator lint_off UNUSEDSIGNAL */
wire [31:0] IRET;
wire [39:0] keysCurrentState;
/* verilator lint_on UNUSEDSIGNAL */

wire keyHalt = keysCurrentState[KEYBOARD_HALT_KEY];
wire keyRun = keysCurrentState[KEYBOARD_RUN_KEY];
wire keyStep = keysCurrentState[KEYBOARD_STEP_KEY];
wire keyNextApp = keysCurrentState[KEYBOARD_NONAME_KEY];

wire Rst_n = KEY[0];

wire Clock_10MHz;
/* verilator lint_off UNUSEDSIGNAL */
wire [INSN_WIDTH - 1:0] Insn;
wire SoftRst_n = Rst_n & ~keysCurrentState[KEYBOARD_SOFT_RST_KEY];
wire HardRst_n = Rst_n & ~keysCurrentState[KEYBOARD_HARD_RST];
/* verilator lint_on UNUSEDSIGNAL */

generate
    if (DIVIDE_TO_01US == 1) begin
        assign Clock_10MHz = FPGA_CLK_50;
    end
    else begin
    ClockDivider #(.DIVISOR({DIVIDE_TO_01US})) clock_divider_10MHz(
        .Rst_n(Rst_n),
        .clock_in(FPGA_CLK_50),
        .clock_out(Clock_10MHz)
    );
    end
endgenerate

ClockDivider #(
    .DIVISOR(10)
) clock_divider_1MHz(
    .Rst_n(Rst_n),
	.clock_in(Clock_10MHz),
	.clock_out(Clock_1MHz)
);

ClockDivider #(
    .DIVISOR({DIVIDE_TO_1MS}),
    .DUTY_CYCLE(80)
) clock_divider_1KHz(
    .Rst_n(Rst_n),
	.clock_in(Clock_1MHz),
	.clock_out(Clock_1KHz)
);

ClockDivider #(
    .DIVISOR({DIVIDE_TO_1S})
) clock_divider_1Hz(
    .Rst_n(Rst_n),
	.clock_in(Clock_1KHz),
	.clock_out(Clock_1Hz)
);

wire EchoMode = 1'b1;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd;

wire [7:0] tx_data;
wire [7:0] rx_data;
BcdToAscii bcdToAscii(tx_data_bcd, tx_data);

AsciiToBcd asciiToBcd(rx_data, rx_data_bcd);

/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApAddress1;
/* verilator lint_on UNDRIVEN */
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] ApData1;
/* verilator lint_on UNUSEDSIGNAL */
wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] IpAddress1;
wire [INSN_WIDTH-1:0] RomData1;

DekatronPC dekatronPC(
    .IpAddress(IpAddress),
    .ApAddress(ApAddress),
    .LoopCount(LoopCount),
    .hsClk(Clock_10MHz),
    .Clk(Clock_1MHz),
    .Rst_n(HardRst_n),
    .Halt(keyHalt),
    .Run(keyRun),
    .InsnIn(4'b0),
    .EchoMode(EchoMode),
    .tx_data_bcd(tx_data_bcd),
    .tx_vld(tx_vld),
    .tx_rdy(tx_rdy),
    .rx_data_bcd(rx_data_bcd),
    .rx_vld(rx_vld),
    .Step(keyStep),
    .key_next_app_i(keyNextApp),
    .IRET(IRET),
    .IpAddress1(IpAddress1),
    .ApAddress1(ApAddress1),
    .ApData1(ApData1),
    .RomData1(RomData1),
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
    .ipAddress1(IpAddress1),
    .RomData1(RomData1),
    .apAddress1(ApAddress1),
    .apData1(ApData1),
    .apData(tx_data_bcd),
    .loopCounter(LoopCount),
    .apAddress(ApAddress),
    .Clock_1s(Clock_1Hz),
    .Clock_1ms(Clock_1KHz),
    .Clock_1us(Clock_1MHz),
    .Rst_n(Rst_n),
    .tx_data(tx_data),
    .tx_vld(tx_vld),
    .DPC_currentState(DPC_currentState)
);

/* verilator lint_off UNUSEDSIGNAL */
wire [127:0] io_input_regs;
/* verilator lint_on UNUSEDSIGNAL */

/* verilator lint_off UNDRIVEN */
wire [127:0] io_output_regs;
/* verilator lint_on UNDRIVEN */

//wire Clock_10KHz;

ClockDivider #(
    .DIVISOR(100)
) clock_divider_100KHz(
    .Rst_n(Rst_n),
	.clock_in(Clock_1MHz),
	.clock_out(Clock_10KHz)
);


io_register_block #(
    .BOARDS(BOARDS),
    .INSTALLED_BOARDS(INSTALLED_BOARDS)
)IoRegisterBlock(
    .Clk(Clock_10KHz),
	.Rst_n(Rst_n),
    .addr_o(io_address),
    .enable_n_o(io_enable_n),
    .data_io(io_data),
    .regs_in_o(io_input_regs),
    .regs_out_i(io_output_regs)
);



logic                        tx_rdy  ;
logic                        tx_vld  ;
//rx signal
wire                          rx_vld  ;

`ifdef CONSUL

wire Clock_100Hz;
ClockDivider #(
    .DIVISOR(10)
) clock_divider_100Hz(
    .Rst_n(Rst_n),
	.clock_in(Clock_1KHz),
	.clock_out(Clock_100Hz)
);

wire [15:0] consul_regs_in;
wire [9:0] consul_regs_out;

assign io_output_regs[31:16]  = 16'hAA55;


assign consul_regs_in = io_input_regs[15:0];
assign io_output_regs[9:0] = consul_regs_out;

logic consul_tx_rdy;
logic consul_tx_vld;
logic consul_tx_rdy_old;

always @(posedge Clock_1MHz, negedge Rst_n) begin
    if (~Rst_n) begin
        consul_tx_rdy_old <= 1'b1;
        tx_rdy <= 1'b1;
        consul_tx_vld <= 1'b0;
    end else begin
        consul_tx_rdy_old <= consul_tx_rdy;
        if (~consul_tx_rdy_old & consul_tx_rdy) begin
            tx_rdy <= 1'b1;
            consul_tx_vld <= 1'b0;
        end
        else begin
            if (tx_vld) begin
                tx_rdy <= 1'b0;
                consul_tx_vld <= 1'b1;
            end
        end
    end
end

consul Consul(
    .Clk(Clock_100Hz),
    .Rst_n(Rst_n),
    .regs_in(consul_regs_in),
    .regs_out(consul_regs_out),
    .print_data_i(tx_data),
    .kb_data_o(rx_data),
    .print_data_vld(consul_tx_vld),
    .kb_data_vld(rx_vld),
    .print_data_rdy(consul_tx_rdy)
);
assign tx = rx;
`else
/* verilator lint_off UNUSEDSIGNAL */
wire                          rx_pc_pass ;
/* verilator lint_on UNUSEDSIGNAL */
wire tx_n;
assign tx = ~tx_n;


uart_tx#(
    .DATA_WIDTH   ( 7   ) ,
    .PARITY_CHECK ( "EVEN" ) ,
    .CLK_FREQ     ( 1000000    ) ,
    .STOP_BITS     (2),
    .BAUD_RATE    ( 650    )
)transmitter(
    .clk    ( Clock_1MHz       ),
    .rst    ( ~Rst_n       ),
    
    .i_vld  ( tx_vld    ),
    .i_data ( tx_data[6:0]   ),
    
    .o_rdy  ( tx_rdy    ),
    .tx     ( tx_n      )
);

uart_rx#(
    .DATA_WIDTH   ( 7   ) ,
    .PARITY_CHECK ( "EVEN" ) ,
    .CLK_FREQ     ( 1000000    ) ,
    .BAUD_RATE    ( 650    )
)receiver(
    .clk     ( Clock_1MHz        ),
    .rst     ( ~Rst_n        ),
    
    .rx      ( ~rx         ),
    .i_rdy   ( 1'b1       ),
    
    .o_vld   ( rx_vld     ),
    .pc_pass ( rx_pc_pass ),
    .o_data  ( rx_data[6:0]    )
) ;

assign rx_data[7] = 1'b0;

`endif

endmodule
