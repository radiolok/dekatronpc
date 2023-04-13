module ApLine #(
    parameter AP_DEKATRON_NUM = 5,
    parameter DATA_DEKATRON_NUM = 3,
    parameter DEKATRON_WIDTH = 4,
    parameter INSN_WIDTH = 4
)(
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,

    output wire dataIsZeroed, 

    input wire Request,
    output wire Ready,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data
);

reg AP_Request;
wire AP_Ready;
wire AP_Zero;
reg AP_Dec;
wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address;

DekatronCounter  #(
            .D_NUM(AP_DEKATRON_NUM),
            .D_WIDTH(DEKATRON_WIDTH)
            )AP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(AP_Request),
                .Dec(AP_Dec),
                .Set(1'b0),
                .In({(AP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(AP_Ready),
                .Out(Address),
                .Zero(AP_Zero)
            );

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCntRoRam;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataRamToCnt;

reg WE_n;
reg CS;

RAM #(
    .ROWS(30000),
    .DATA_WIDTH(8)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(Address),
    .In(DataCntRoRam),
    .Out(DataRamToCnt),
    .WE_n(WE_n),
    .CS(CS)
);

reg Data_Request;
reg Data_Dec;
wire Data_Ready;

DekatronCounter  #(
            .D_NUM(DATA_DEKATRON_NUM),
            .D_WIDTH(DEKATRON_WIDTH)
            )Data_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Data_Request),
                .Dec(Data_Dec),
                .Set(1'b0),
                .In(DataRamToCnt),
                .Ready(Data_Ready),
                /* verilator lint_off PINCONNECTEMPTY */
                .Out(DataCntRoRam),
                /* verilator lint_on PINCONNECTEMPTY */
                .Zero(dataIsZeroed)
            );

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        AP_Request <= 1'b0;
        Data_Request <= 1'b0;
        AP_Dec <= 1'b0;
        Data_Dec <= 1'b0;
        WE_n <= 1'b0;
        CS <= 1'b0;
    end

end


endmodule
