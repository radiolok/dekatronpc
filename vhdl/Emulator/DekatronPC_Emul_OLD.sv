
module DekatronPC(
    output reg  [17:0] ipCounter,
    output reg [8:0] loopCounter,
    output reg [14:0] apCounter,
    output reg [8:0] dataCounter,
    input wire Clock_1ms,
    input wire Rst_n,
    input wire [39:0] keysCurrentState,
    input wire [7:0] symbol,    
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


always @(posedge Clock_1ms, negedge Rst_n) begin
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

always @(posedge Clock_1ms, negedge Rst_n) begin
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
reg [7:0] symbolOld;


always @(posedge Clock_1ms, negedge Rst_n) begin
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
        symbolOld <= 0;
	end
	else begin
        IncKeyOld <= IncKey;
        DecKeyOld <= DecKey;
        prevStepKey <= currentStepKey;
        ArrowUpKeyOld <= ArrowUpKey;
        ArrowDownKeyOld <= ArrowDownKey;
        ArrowLeftKeyOld <= ArrowLeftKey;
        ArrowRightKeyOld <= ArrowRightKey;
        symbolOld <= symbol;

        if ((DPC_currentState == DPC_HARD_RST) || 
            (DPC_currentState == DPC_SOFT_RST)) begin
                ipCounter <= 1'b0;
                loopCounter <= 1'o0;
                apCounter <= 1'o0;
                dataCounter <= 1'o0;
            end
        else if ((DPC_currentState == DPC_STEP) || 
            (DPC_currentState == DPC_RUN)) begin
                ipCounter <= ipCounter + 1'b1;
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
                ipCounter  <=  ipCounter - 18'h10;
            end
            else  if ((ArrowDownKey & ~ ArrowDownKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter + 18'h10;
            end
            else  if ((ArrowLeftKey & ~ ArrowLeftKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter - 18'h1;
            end
            else  if ((ArrowRightKey & ~ ArrowRightKeyOld) && (currentCounter == IP_COUNTER)) begin
                ipCounter  <=  ipCounter + 18'h1;
            end
            else  if (symbol & ~ symbolOld) begin
                ipCounter  <=  ipCounter + 18'h1;
            end                           
        end
	end
end


endmodule

