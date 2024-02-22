/* verilator lint_off DECLFILENAME */
module OneShot #(
    parameter DELAY=1'b1,
    parameter WIDTH=$clog2(DELAY)
)(
    input Clk,
    input En,
    input Rst_n,
    output wire Impulse
);
//synopsys translate_off
localparam DELAY_COMP=DELAY-1;
reg [WIDTH:0] count;
assign Impulse = (|count) | En;

always @(posedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        count <= 0;
    end
    else begin
        if (En | Impulse) begin
            count <= count + 1;
            if (count == DELAY_COMP) begin
                count <= 0;
            end
        end
    end
end
//synopsys translate_on
endmodule

module OneShot_tb();

reg Clk = 1'b0;
reg Rst_n = 1'b0;
reg En;
wire Impulse;

//synopsys translate_off

initial begin $dumpfile("OneShot_tb.vcd"); 
$dumpvars(0,OneShot_tb); end

OneShot #(.DELAY(10)
)oneshot(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .En(En),
    .Impulse(Impulse)
);

initial begin
    Clk <= 1'b0;
    forever #1 Clk = ~Clk;
end

initial
begin
	#3
	Rst_n <= 1'b1;
	$display($time, " << Starting Simulation >> ");
	
	#400;
	$display($time, "<< Simulation Complete >>");
	$finish;
end

always @(posedge Clk) begin
    if (~Impulse)
        En <= 1'b1;
    else
        En <= 1'b0;
end
//synopsys translate_on
endmodule
/* verilator lint_on DECLFILENAME */
