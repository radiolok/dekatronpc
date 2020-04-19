module Register(Wr, Rd, Rst, In, Out);

parameter WIDTH=8;

input wire Wr;
input wire Rd;
input wire Rst;
input wire[WIDTH-1:0] In;
inout wire[WIDTH-1:0] Out;

reg [WIDTH-1:0] Mem;

always @(Wr, Rd, Rst) begin
    if (~Rst)  Mem <= WIDTH'b0;
    else
    {
        if (Wr) Mem <= In;
        Out <= Rd? Mem : WIDTH'bz;
    }
end

endmodule