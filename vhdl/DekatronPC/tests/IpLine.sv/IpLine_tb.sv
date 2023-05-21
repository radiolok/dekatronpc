`timescale 1ns/1ps

module IpLine_tb (
);
reg Rst_n;
reg Clk;
reg hsClk;
initial begin
    hsClk = 1'b1;
    forever #50 hsClk = ~hsClk;
end
parameter TEST_NUM=200;
reg [$clog2(TEST_NUM):0] test_num=TEST_NUM;
ClockDivider #(
    .DIVISOR(10)
) clock_divider_ms(
    .Rst_n(Rst_n),
	.clock_in(hsClk),
	.clock_out(Clk)
);
wire dataIsZeroed;
reg Request = 1'b0;

wire Ready;

wire [3:0] Insn;

wire [6*4-1:0] Address;


wire RomRequest;
wire RomReady;
wire [INSN_WIDTH-1:0] RomData;

ROM #(
        .D_NUM(IP_DEKATRON_NUM),
        .DATA_WIDTH(INSN_WIDTH)
        )rom(
        .Rst_n(Rst_n),
        .Clk(Clk), 
        .Address(Address),
        .Insn(RomData),
        .Request(RomRequest),
        .Ready(RomReady)
        );

IpLine  ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .hsClk(hsClk),
    .dataIsZeroed(dataIsZeroed),
    .Request(Request),
    .Ready(Ready),
    .IpAddress(Address),
    .RomRequest(RomRequest),
    .RomReady(RomReady),
    .RomData(RomData),
    .Insn(Insn)
);
initial begin $dumpfile("IpLine_tb.vcd"); $dumpvars(0,IpLine_tb); end

reg Busy;

reg [10:0] Data;
reg [31:0] INSN_RETIRED;
assign dataIsZeroed = (Data == 0);


reg [31:0] CLOCK_TICK;

always @(posedge Clk) begin
  if (~Rst_n) begin
    CLOCK_TICK <= 0;
  end
   else 
       CLOCK_TICK <= CLOCK_TICK + 1;
       if (CLOCK_TICK > 2000)
          $fatal(1, "Timeout");
end
initial begin 
Rst_n <= 0;
Data <= 0;
Busy <= 0;

#5 
Rst_n <= 1;


for (integer i = 0; i < TEST_NUM; i++) begin

  repeat(1) @(posedge Request)
  repeat(1) @(posedge Ready)
  $display("IRET:%d Time: %dus Addr: %h Insn: %b, Data: %d(%b)", i, $time/1000, Address, Insn, Data, dataIsZeroed);
  
  case (Insn)
  4'b0010: Data <= Data + 1;
  4'b0011: Data <= Data - 1;
  4'b0001: begin 
        $display ("CLOCKTICK: %dus", CLOCK_TICK); 
        if (Data) 
          $fatal(1, "Data not zero");
        else
          $finish; 
  end
  endcase

  if ((Address > 8'b00010111) | (Address[23:20]))
    $fatal(1, "Address is out of scope");
end
$fatal;

end

always @(posedge Clk) begin
    if (~Rst_n)
        Request <= 0;
    else
        if (Ready)
            Request <= 1'b1;
        if (Request)
            Request <= 1'b0;
end

endmodule
