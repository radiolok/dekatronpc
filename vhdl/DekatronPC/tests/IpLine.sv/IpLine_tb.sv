module ip_line_tb #(
);

reg Clk;
reg Rst_n;
wire dataIsZeroed;
reg Request;

wire Ready;

wire [3:0] Insn;

wire [6*3-1:0] Address;

IpLine  ipLine(
    .Rst_n(Rst_n),
    .Clk(Clk),
    .dataIsZeroed(dataIsZeroed),
    .Request(Request),
    .Ready(Ready),
    .Address(Address),
    .Insn(Insn)
);

initial begin
    Clk = 1'b0;
    forever #1 Clk = ~Clk;
end

initial begin
    Rst_n <= 0;
    #1  Rst_n <= 1;
end

reg Busy;

reg [10:0] Data;
assign dataIsZeroed = (Data == 0);

always @(posedge Clk, Rst_n) begin
    if (~Rst_n) begin
        Request <= 0;
        Busy <= 0;
        Data <= 0;
    end
    else
        if (~Busy & Ready) begin
            Busy <= 1'b1;
            Request <= 1'b1;
            $display("Time: %d Addr: %h Insn: %b, Data: %d(%b)", $time, Address, Insn, Data, dataIsZeroed);
        end
        if (Request & ~Ready) begin
            Request <= 1'b0;
        end
        if (Busy & Ready) begin
            Busy <= 1'b0;
            case (Insn)
                4'b0010: Data <= Data + 1;
                4'b0011: Data <= Data - 1;
                4'b0001: $stop;
            endcase
                
        end
end

endmodule