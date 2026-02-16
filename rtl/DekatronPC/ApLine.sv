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
    input wire ram_rdy_i,

    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataIn,
    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] RamDataOut,
    output reg RamWE,
    output wire RamCS,

    input wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] rx_data_bcd,
    output wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] tx_data_bcd

);

reg cnt_ap_request;
wire cnt_ap_ready;
reg cnt_data_request;
wire cnt_data_ready;

reg cnt_data_set;
reg MemLock;
assign RamCS = 1'b1;

typedef enum logic [4:0] {
    IDLE     =  5'b00001,
    LOAD     =  5'b00010,
    STORE    =  5'b00100,
    CIN      =  5'b01000,
    COUNT     = 5'b10000
} ap_line_state_t;

ap_line_state_t currentState, nextState;

assign Ready = (nextState == IDLE) & cnt_ap_ready & cnt_data_ready;


wire DataCtrZero;
wire DataMemZero;
assign DataMemZero = ~(|RamDataOut);
assign DataZero = MemLock ? DataCtrZero : DataMemZero;

DekatronCounter  #(
            .D_NUM(AP_DEKATRON_NUM),
            .WRITE(1'b0),
            .TOP_LIMIT_MODE(1'b1),
            .TOP_VALUE({4'd2, 4'd9, 4'd9, 4'd9, 4'd9})
            )AP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(cnt_ap_request),
                .Dec(Dec),
                .Set(1'b0),
                .SetZero(Zero),
                .In({(AP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(cnt_ap_ready),
                .Out(Address),
                .Zero(ApZero)
            );


wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCounterIn;
assign DataCounterIn = (currentState == CIN) ? rx_data_bcd : RamDataOut;

wire [DATA_DEKATRON_NUM*DEKATRON_WIDTH-1:0] DataCounterOut;
//COUT tx_data_bcd
assign tx_data_bcd = MemLock ? DataCounterOut : RamDataOut;

assign RamDataIn = ( currentState == CIN ) ? rx_data_bcd : DataCounterOut;

DekatronCounter  #(
            .D_NUM(DATA_DEKATRON_NUM),
            .WRITE(1'b1),
            .TOP_LIMIT_MODE(1'b1),
            .TOP_VALUE({4'd2, 4'd5, 4'd5})
            )Data_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(cnt_data_request),
                .Dec(Dec),
                .Set(cnt_data_set),
                .SetZero(Zero),
                .In(DataCounterIn),
                .Ready(cnt_data_ready),
                .Out(DataCounterOut),
                .Zero(DataCtrZero)
            );


always_comb begin
    nextState = currentState;
    case (currentState)
        IDLE: begin
            if (ApRequest & ram_rdy_i) begin
                if (MemLock) begin
                    nextState = STORE;
                end else begin
                    nextState = COUNT;
                end
            end else begin
                if (DataRequest & ram_rdy_i) begin
                    if (Cin) begin
                        nextState = CIN;
                    end else begin
                        if (MemLock) begin
                            nextState = COUNT;
                        end else begin
                            nextState = LOAD;
                        end
                    end
                end
            end
        end
        CIN: begin
            if (cnt_data_request & cnt_data_ready) begin
                nextState = IDLE;
            end else begin
                nextState = CIN;
            end
        end
        LOAD: begin
            if (cnt_data_request & cnt_data_ready) begin
                nextState = COUNT;
            end else begin
                nextState = LOAD;
            end
        end
        STORE: begin//????
            nextState = COUNT;
        end
        COUNT: begin
            if ((cnt_ap_request & cnt_ap_ready) |
                (cnt_data_request & cnt_data_ready)) begin
                nextState = IDLE;
            end else begin
                nextState = COUNT;
            end
        end

    endcase
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        currentState <= IDLE;
    end else begin
        currentState <= nextState;
    end
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        cnt_ap_request <= 1'b0;
        cnt_data_request <= 1'b0;
        cnt_data_set <= 1'b0;
        RamWE <= 1'b0;
        MemLock <= 1'b0;
    end
    else begin
        case (nextState)
            IDLE: begin
                cnt_ap_request   <= 1'b0;
                cnt_data_request <= 1'b0;
                cnt_data_set     <= 1'b0;
                RamWE            <= 1'b0;
            end
            LOAD: begin
                cnt_ap_request   <= 1'b0;
                cnt_data_request <= 1'b1;
                cnt_data_set     <= 1'b1;
                RamWE            <= 1'b0;
                MemLock          <= 1'b1;
            end
            STORE: begin
                cnt_ap_request   <= 1'b0;
                cnt_data_request <= 1'b1;
                cnt_data_set     <= 1'b0;
                RamWE            <= 1'b1;
                MemLock          <= 1'b0;
            end
            COUNT: begin
                cnt_ap_request   <= ~(MemLock);
                cnt_data_request <= (MemLock);
                cnt_data_set     <= 1'b0;
                RamWE            <= 1'b0;
            end
            CIN: begin
                cnt_ap_request   <= 1'b0;
                cnt_data_request <= 1'b1;
                cnt_data_set     <= 1'b1;
                RamWE            <= 1'b0;
            end
        endcase
    end
end



endmodule
