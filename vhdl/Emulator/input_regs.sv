module input_regs #(
    parameter BOARDS = 16
)(
    input wire [3:0] reg_num,
    input wire ReadEnable,
    input wire Clk,
    input wire Rst_n,
    input wire [7:0] data,
    output wire [BOARDS*8-1:0] outputs
);

reg [7:0] regs [0:BOARDS-1];


assign  outputs = { regs[15],  regs[14],  regs[13],  regs[12],  
                regs[11],  regs[10],  regs[9],   regs[8],   
                regs[7],   regs[6],   regs[5],   regs[4], 
                regs[3],   regs[2],   regs[1],   regs[0]};    


always @(negedge Clk, negedge Rst_n) begin
    if (~Rst_n) begin
        regs[0] <=0;
        regs[1] <=0;
        regs[2] <=0;
        regs[3] <=0;
        regs[4] <=0;
        regs[5] <=0;
        regs[6] <=0;
        regs[7] <=0;
        regs[8] <=0;
        regs[9] <=0;
        regs[10] <=0;
        regs[11] <=0;
        regs[12] <=0;
        regs[13] <=0;
        regs[14] <=0;
        regs[15] <=0;
    end else begin
    if (ReadEnable) begin
        regs[reg_num] <= data;
	 end
	 end
end

endmodule
