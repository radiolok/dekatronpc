module Register(Wr, Rd, Rst_n, In, Out);

parameter WIDTH=8;

input wire Wr;
input wire Rd;
input wire Rst_n;
input wire[WIDTH-1:0] In;
inout wire[WIDTH-1:0] Out;

reg [WIDTH-1:0] Mem;

assign Out = Rd? Mem : {WIDTH{1'bz}};

always @(Wr, Rst_n) begin
	Mem <= (Rst_n) ? ((Wr) ? In : Mem) : {WIDTH{1'b0}};    
end

endmodule