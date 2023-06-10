module ApLine (
    input wire Rst_n,
    input wire Clk,
    input wire hsClk,

    output wire DataZero,
    output wire ApZero,

    input wire ApRequest,
    input wire DataRequest,
    input wire Dec,
    input wire Zero,
    input wire Cin,
    
    output wire Ready,

    output wire [AP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,

    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataIn,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataOut,
    output reg RamWE,
    output wire RamCS,

    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCin,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Data

);

reg AP_Request;
wire AP_Ready;
reg Data_Request;
reg DataCounterSet;
wire Data_Ready;
reg MemLock;
assign RamCS = 1'b1;

parameter [3:0]
    IDLE     =  4'b0001,
    LOAD     =  4'b0010,
    STORE    =  4'b0100,
    COUNT     = 4'b1000;

reg [3:0] currentState;

assign Ready = ~ApRequest & ~DataRequest & (currentState == IDLE) & AP_Ready & Data_Ready;


wire DataCtrZero;
wire DataMemZero;
assign DataMemZero = ~(|RamDataOut);
assign DataZero = MemLock ? DataCtrZero : DataMemZero;

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
                .SetZero(Zero),
                .In({(AP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(AP_Ready),
                .Out(Address),
                .Zero(ApZero)
            );


wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCounterIn;
assign DataCounterIn = (Cin) ? DataCin : RamDataOut;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCounterOut;
//COUT data
assign Data = MemLock ? DataCounterOut : RamDataOut;

assign RamDataIn = ( Cin ) ? DataCin : DataCounterOut;

DekatronCounter  #(
            .D_NUM(DATA_DEKATRON_NUM),
            .WRITE(1'b1),
            .TOP_LIMIT_MODE(1'b1),
            .TOP_VALUE({4'd2, 4'd5, 4'd5})
            )Data_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(Data_Request),
                .Dec(Dec),
                .Set(DataCounterSet),
                .SetZero(Zero),
                .In(DataCounterIn),
                .Ready(Data_Ready),
                .Out(DataCounterOut),
                .Zero(DataCtrZero)
            );

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        AP_Request <= 1'b0;
        Data_Request <= 1'b0;
        RamWE <= 1'b0;
        MemLock <= 1'b0;
        DataCounterSet <= 1'b0;
        currentState <= IDLE;
    end
    else begin
        case (currentState)
            IDLE: begin
                if (ApRequest) begin
                    if (MemLock) begin 
                        currentState <= STORE;
                        RamWE <= 1'b1;
                    end
                    else begin
                        currentState <= COUNT;
                        AP_Request <= 1'b1;
                    end                    
                end
                if (DataRequest) begin
                    if (~MemLock) begin
                        currentState <= LOAD;
                        DataCounterSet <= 1'b1;
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
                DataCounterSet <= 1'b0;
                if (Data_Ready) begin
                    Data_Request <= 1'b1;
                    currentState <= COUNT;
                end
            end
            STORE: begin
                RamWE <= 1'b0;
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
