`include "parameters.sv"

module ApLine (
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,

    output wire DataZero,
    output wire ApZero,

    input wire ApRequest,
    input wire DataRequest,
    input wire Dec,
    
    output wire Ready,

    `ifdef EMULATOR
    input wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address1,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data1,
    `endif

    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data

);

reg AP_Request;
wire AP_Ready;
reg WE;
reg Data_Request;
reg Data_Set;
wire Data_Ready;
reg MemLock;

parameter [3:0]
    IDLE     =  4'b0001,
    LOAD     =  4'b0010,
    STORE    =  4'b0100,
    COUNT     = 4'b1000;

reg [3:0] currentState;

assign Ready = ~ApRequest & ~DataRequest & currentState[0] & AP_Ready & Data_Ready;

assign Data = MemLock? DataCntRoRam : DataRamToCnt;

DekatronCounter  #(
            .D_NUM(AP_DEKATRON_NUM),
            .WRITE(1'b0)
            )AP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(AP_Request),
                .Dec(Dec),
                .Set(1'b0),
                .SetZero(1'b0),
                .In({(AP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(AP_Ready),
                .Out(Address),
                .Zero(ApZero)
            );

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCntRoRam;
wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataRamToCnt;


RAM #(
    .ROWS(170393),
    .DATA_WIDTH(12)
) ram(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Address(Address[17:0]),
    .In(DataCntRoRam),
    .Out(DataRamToCnt),
`ifdef EMULATOR
    .Address1(Address1),
    .Out1(Data1),
`endif
    .WE(WE),
    .CS(1'b1)
);

DekatronCounter  #(
            .D_NUM(DATA_DEKATRON_NUM)
            )Data_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Data_Request),
                .Dec(Dec),
                .Set(Data_Set),
                .SetZero(1'b0),
                .In(DataRamToCnt),
                .Ready(Data_Ready),
                .Out(DataCntRoRam),
                .Zero(DataZero)
            );


always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        AP_Request <= 1'b0;
        Data_Request <= 1'b0;
        WE <= 1'b0;
        MemLock <= 1'b0;
        Data_Set <= 1'b0;
        currentState <= IDLE;
    end
    else begin
        case (currentState)
            IDLE: begin
                if (ApRequest) begin
                    if (MemLock) begin 
                        currentState <= STORE;
                        WE <= 1'b1;
                    end
                    else begin
                        currentState <= COUNT;
                        AP_Request <= 1'b1;
                    end                    
                end
                if (DataRequest) begin
                    if (~MemLock) begin
                        currentState <= LOAD;
                        Data_Set <= 1'b1;
                        Data_Request <= 1'b1;
                    end
                    else begin
                        currentState <= COUNT;
                        Data_Request <= 1'b1;
                    end 
                end
            end
            LOAD: begin
                MemLock <= 1'b1;
                Data_Request <= 1'b0;                
                Data_Set <= 1'b0;
                if (Data_Ready) begin
                    Data_Request <= 1'b1;
                    currentState <= COUNT;
                end
            end
            STORE: begin
                WE <= 1'b0;
                MemLock <= 1'b0;
                currentState <= COUNT;
                AP_Request <= 1'b1;
            end
            COUNT: begin
                AP_Request <= 1'b0;
                Data_Request <= 1'b0;
                if (AP_Ready | Data_Ready) begin
                    currentState <= IDLE;
                end
                end
            default:
                currentState <= IDLE;
        endcase
    end
end



endmodule
