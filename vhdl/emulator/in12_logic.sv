module UpCounter #(
    parameter TOP = 4'b1001,
    parameter WIDTH=4
)(
    input wire Tick,
    input wire Rst_n,
    output reg [WIDTH-1:0] Count
);

always @(posedge Tick, negedge Rst_n) begin
    Count <=  (!Rst_n) ? {WIDTH{1'b0}} :
            (Count == TOP) ? {WIDTH{1'b0}}:
            Count + 1;
end

endmodule

module in12_cathodeToPinConverter(
    input wire [3:0] in,
    output reg[3:0] out
);

always @(*)
case (in)
    4'b0000: out = 4'b0001;
    4'b0001: out = 4'b0000;
    4'b0010: out = 4'b0010;
    4'b0011: out = 4'b0011;
    4'b0100: out = 4'b0110;
    4'b0101: out = 4'b1000;
    4'b0110: out = 4'b1001;
    4'b0111: out = 4'b0111;
    4'b1000: out = 4'b0101;
    4'b1001: out = 4'b0100;
    default: out = 4'b1010;
endcase

endmodule

module DekatronPC(
    output reg  [17:0] ipCounter,
    output reg [8:0] loopCounter,
    output reg [14:0] apCounter,
    output reg [8:0] dataCounter,
    input wire Clk,
    input wire Rst_n,
    input wire [39:0] keysCurrentState,
    output wire [2:0] DPC_currentState
);

`include "keyboard_keys.sv" 


parameter [2:0]
    NONE_COUNTER = 3'b000,
    IP_COUNTER = 3'b001,
    AP_COUNTER = 3'b010,
    LOOP_COUNTER = 3'b011,
    DATA_COUNTER = 3'b100;
reg [2:0] currentCounter;
reg [2:0] nextCounter;


always @(*) begin
    case (currentCounter)
        NONE_COUNTER:
            if (keysCurrentState[KEYBOARD_IP_KEY])
                nextCounter = IP_COUNTER;
            else if (keysCurrentState[KEYBOARD_AP_KEY])
                nextCounter = AP_COUNTER;
            else if (keysCurrentState[KEYBOARD_LOOP_KEY])
                nextCounter = LOOP_COUNTER;
            else if (keysCurrentState[KEYBOARD_DATA_KEY])
                nextCounter = DATA_COUNTER;
            else 
                nextCounter = NONE_COUNTER;
        IP_COUNTER:
            if (keysCurrentState[KEYBOARD_AP_KEY])
                nextCounter = AP_COUNTER;
            else if (keysCurrentState[KEYBOARD_LOOP_KEY])
                nextCounter = LOOP_COUNTER;
            else if (keysCurrentState[KEYBOARD_DATA_KEY])
                nextCounter = DATA_COUNTER;
            else 
                nextCounter = IP_COUNTER;
        AP_COUNTER:
            if (keysCurrentState[KEYBOARD_IP_KEY])
                nextCounter = IP_COUNTER;
            else if (keysCurrentState[KEYBOARD_LOOP_KEY])
                nextCounter = LOOP_COUNTER;
            else if (keysCurrentState[KEYBOARD_DATA_KEY])
                nextCounter = DATA_COUNTER;
            else 
                nextCounter = AP_COUNTER;
        LOOP_COUNTER:
            if (keysCurrentState[KEYBOARD_IP_KEY])
                nextCounter = IP_COUNTER;
            else if (keysCurrentState[KEYBOARD_AP_KEY])
                nextCounter = AP_COUNTER;
            else if (keysCurrentState[KEYBOARD_DATA_KEY])
                nextCounter = DATA_COUNTER;
            else 
                nextCounter = LOOP_COUNTER;
        DATA_COUNTER:
            if (keysCurrentState[KEYBOARD_IP_KEY])
                nextCounter = IP_COUNTER;
            else if (keysCurrentState[KEYBOARD_AP_KEY])
                nextCounter = AP_COUNTER;
            else if (keysCurrentState[KEYBOARD_LOOP_KEY])
                nextCounter = LOOP_COUNTER;
            else 
                nextCounter = DATA_COUNTER;
    endcase
end


always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        currentCounter <= NONE_COUNTER;
    end
    else begin
        currentCounter <= nextCounter;
    end
end


reg [2:0] DPC_nextState;
reg [2:0] DPC_currentStateInt;

parameter [2:0]
    DPC_HARD_RST = 0,
    DPC_SOFT_RST = 1,
    DPC_HALT = 2,
    DPC_STEP = 3,
    DPC_RUN = 4;

assign DPC_currentState = DPC_currentStateInt;

wire currentStepKey = keysCurrentState[KEYBOARD_STEP_KEY];
reg prevStepKey;

always @* begin
    case (DPC_currentStateInt)
        DPC_HARD_RST:
            if (keysCurrentState[KEYBOARD_SOFT_RST_KEY])
                DPC_nextState = DPC_SOFT_RST;
            else if (currentStepKey & ~prevStepKey)
                DPC_nextState = DPC_STEP;
            else if (keysCurrentState[KEYBOARD_RUN_KEY])
                DPC_nextState = DPC_RUN;
            else
                DPC_nextState = DPC_HALT;
        DPC_SOFT_RST:
            if (keysCurrentState[KEYBOARD_HARD_RST])
                DPC_nextState = DPC_HARD_RST;
            else if (currentStepKey & ~prevStepKey)
                DPC_nextState = DPC_STEP;
            else if (keysCurrentState[KEYBOARD_RUN_KEY])
                DPC_nextState = DPC_RUN;
            else
                DPC_nextState = DPC_HALT;
        DPC_STEP:
            if (keysCurrentState[KEYBOARD_HARD_RST])
                DPC_nextState = DPC_HARD_RST;
            else if (keysCurrentState[KEYBOARD_SOFT_RST_KEY])
                DPC_nextState = DPC_SOFT_RST;
            else if (keysCurrentState[KEYBOARD_RUN_KEY])
                DPC_nextState = DPC_RUN;
            else
                DPC_nextState = DPC_HALT;
        DPC_RUN:
            if (keysCurrentState[KEYBOARD_HARD_RST])
                DPC_nextState = DPC_HARD_RST;
            else if (keysCurrentState[KEYBOARD_SOFT_RST_KEY])
                DPC_nextState = DPC_SOFT_RST;
            else if (keysCurrentState[KEYBOARD_HALT_KEY])
                DPC_nextState = DPC_HALT;
            else if (currentStepKey & ~prevStepKey)
                DPC_nextState = DPC_STEP;
            else
                DPC_nextState = DPC_RUN;
        DPC_HALT:
            if (keysCurrentState[KEYBOARD_HARD_RST])
                DPC_nextState = DPC_HARD_RST;
            else if (keysCurrentState[KEYBOARD_SOFT_RST_KEY])
                DPC_nextState = DPC_SOFT_RST;
            else if (currentStepKey & ~prevStepKey)
                DPC_nextState = DPC_STEP;
            else if (keysCurrentState[KEYBOARD_RUN_KEY])
                DPC_nextState = DPC_RUN;
            else
                DPC_nextState = DPC_HALT;
        default: 
            DPC_nextState = DPC_HALT;
    endcase
end

always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) begin
		DPC_currentStateInt <= DPC_HARD_RST;
	end
	else begin
		DPC_currentStateInt <= DPC_nextState;
	end
end

wire IncKey = keysCurrentState[KEYBOARD_INC_KEY];
wire DecKey = keysCurrentState[KEYBOARD_DEC_KEY];
wire ArrowUpKey = keysCurrentState[KEYBOARD_ARROW_UP_KEY];
wire ArrowDownKey = keysCurrentState[KEYBOARD_ARROW_DOWN_KEY];
wire ArrowLeftKey = keysCurrentState[KEYBOARD_ARROW_LEFT_KEY];
wire ArrowRightKey = keysCurrentState[KEYBOARD_ARROW_RIGHT_KEY];
reg IncKeyOld;
reg DecKeyOld;
reg ArrowUpKeyOld;
reg ArrowDownKeyOld;
reg ArrowLeftKeyOld;
reg ArrowRightKeyOld;


always @(posedge Clk, negedge Rst_n) begin
	if (~Rst_n) begin
        ipCounter <= 'o0;
        loopCounter <= 'o0;
        apCounter <= 'o0;
        dataCounter <= 'o0;
        IncKeyOld <= 0;
        DecKeyOld <= 0;
        prevStepKey <= 0;
        ArrowUpKeyOld <= 0;
        ArrowDownKeyOld <= 0;
        ArrowLeftKeyOld <= 0;
        ArrowRightKeyOld <= 0;
	end
	else begin
        IncKeyOld <= IncKey;
        DecKeyOld <= DecKey;
        prevStepKey <= currentStepKey;
        ArrowUpKeyOld <= ArrowUpKey;
        ArrowDownKeyOld <= ArrowDownKey;
        ArrowLeftKeyOld <= ArrowLeftKey;
        ArrowRightKeyOld <= ArrowRightKey;

        if ((DPC_currentState == DPC_HARD_RST) || 
            (DPC_currentState == DPC_SOFT_RST)) begin
                ipCounter <= 'b0;
                loopCounter <= 'o0;
                apCounter <= 'o0;
                dataCounter <= 'o0;
            end
        else if ((DPC_currentState == DPC_STEP) || 
            (DPC_currentState == DPC_RUN)) begin
                ipCounter <= ipCounter + 'b1;
            end
        else begin
            if (IncKey & ~ IncKeyOld) begin
                case (currentCounter)
                IP_COUNTER:
                    ipCounter  <=  ipCounter + 1'b1 ;
                AP_COUNTER:
                    apCounter  <=  apCounter + 1'b1 ;
                LOOP_COUNTER:
                    loopCounter  <= loopCounter + 1'b1 ;
                DATA_COUNTER:
                    dataCounter  <= dataCounter + 1'b1;
                endcase
            end
            else  if (DecKey & ~ DecKeyOld) begin
                case (currentCounter)
                IP_COUNTER:
                    ipCounter  <=  ipCounter - 1'b1 ;
                AP_COUNTER:
                    apCounter  <=  apCounter - 1'b1 ;
                LOOP_COUNTER:
                    loopCounter  <= loopCounter - 1'b1 ;
                DATA_COUNTER:
                    dataCounter  <= dataCounter - 1'b1;
                endcase
            end
            else  if ((ArrowUpKey & ~ ArrowUpKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter - 'h10;
            end
            else  if ((ArrowDownKey & ~ ArrowDownKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter + 'h10;
            end
            else  if ((ArrowLeftKey & ~ ArrowLeftKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter - 'h1;
            end
            else  if ((ArrowRightKey & ~ ArrowRightKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter + 'h1;
            end                        
        end
	end
end


endmodule

module Impulse(
    input Clock,
    input Enable,
    input Rst_n,
    output wire Impulse
);

reg D_state;

assign Impulse = Enable & ~D_state;


always @(negedge Clock, negedge Rst_n) begin
    if (~Rst_n) begin
        D_state <= 1'b0;
    end
    else
    begin
        D_state <= Enable;
    end
end

endmodule