`include "parameters.sv"

module IpCounter(	
	input wire Clk,
    input wire hsClk,
	input wire Rst_n,

    // All changes start on Request
    //If Set == 1, Out <= In
    //If Dec = 1, Out <= Out-1
    //Else, Out <= Out + 1
    input wire Request,
    input wire Dec,

	output wire Ready,
    output wire [IP_DEKATRON_NUM*DEKATRON_WIDTH-1:0] Address,
	output wire[INSN_WIDTH-1:0] Insn
);

reg IP_Request;
wire IP_Ready;

DekatronCounter  #(
            .D_NUM(IP_DEKATRON_NUM)
            )IP_counter(
                .Clk(Clk),
                .hsClk(hsClk),
                .Rst_n(Rst_n),
                .Request(IP_Request),
                .Dec(Dec),
                .Set(1'b0),
                .In({(IP_DEKATRON_NUM*DEKATRON_WIDTH){1'b0}}),
                .Ready(IP_Ready),
                .Out(Address),
                /* verilator lint_off PINCONNECTEMPTY */
                .Zero()
                /* verilator lint_on PINCONNECTEMPTY */
            );

reg ROM_Request;
wire ROM_DataReady;

ROM #(
        .D_NUM(IP_DEKATRON_NUM),
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(Address),
        .Insn(Insn),
        .Request(ROM_Request),
        .DataReady(ROM_DataReady)
        );

parameter [3:0]
    IDLE     =  4'b0001,
    IP_COUNT =  4'b0010,
    ROM_COUNT = 4'b0100,
    READY     = 4'b1000;

reg [3:0] currentState;
assign Ready = ~Request & (currentState[3] | currentState[0]);//READY | IDLE

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        IP_Request <= 1'b0;
        ROM_Request <= 1'b0;
        currentState <= IDLE;
    end
    else begin
        case (currentState)
            IDLE:
                if (Request) begin
                    if (ROM_DataReady) begin
                        IP_Request <= 1'b1;
                        currentState <= IP_COUNT;
                    end
                    else begin
                        ROM_Request <= 1'b1;
                        currentState <= ROM_COUNT;
                    end
                end
            IP_COUNT: begin
                IP_Request <= 1'b0;
                if (IP_Ready & Clk) begin
                    ROM_Request <= 1'b1;
                    currentState <= ROM_COUNT;
                end
            end
            ROM_COUNT: begin                
                ROM_Request <= 1'b0;
                if (ROM_DataReady & Clk) begin
                    currentState <= READY;
                end
            end
            READY:
                if (~Request) begin
                    currentState <= IDLE;
                end
            default:
                currentState <=IDLE;
        endcase        
    end    
end
endmodule
