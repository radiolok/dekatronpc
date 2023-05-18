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
            .D_NUM(IP_DEKATRON_NUM),
		    .WRITE(1'b0)
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

parameter [1:0]
    IDLE     =  2'b00,
    IP_COUNT =  2'b01,
    ROM_COUNT = 2'b10,
    READY     = 2'b11;

reg [1:0] state, next;
assign Ready = ~Request & ~(^state);//READY | IDLE


always @(posedge Clk or negedge Rst_n) begin
    if (~Rst_n)  state <= IDLE;
    else state <= next;
end

always_comb begin
    case (state)
        IDLE: begin
            if (Request) next <= (ROM_DataReady)? IP_COUNT : ROM_COUNT;
            else next <= IDLE;
        end
        IP_COUNT: begin
            if (IP_Ready) next <= ROM_COUNT;
            else next <= IP_COUNT;
        end
        ROM_COUNT: begin
            if (ROM_DataReady) next <= READY;
            else next <= ROM_COUNT;
        end
        READY: begin
            next <= IDLE;
        end
    endcase
end

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        IP_Request <= 1'b0;
        ROM_Request <= 1'b0;
    end
    else begin
        case (state)
            IDLE: begin
                IP_Request <= 1'b0;
                ROM_Request <= 1'b0;
            end
            IP_COUNT: begin
                IP_Request <= 1'b1;
                ROM_Request <= 1'b0;
            end
            ROM_COUNT: begin    
                IP_Request <= 1'b0;
                ROM_Request <= 1'b1;
            end
            READY: begin
                IP_Request <= 1'b0;
                ROM_Request <= 1'b0;
            end
            default: begin
                IP_Request <= 1'b0;
                ROM_Request <= 1'b0;
            end
        endcase        
    end    
end
endmodule
