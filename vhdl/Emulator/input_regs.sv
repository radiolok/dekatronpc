module input_regs #(
    parameter BOARDS = 16
)(
    input wire [3:0] reg_num,
    input wire ReadEnable,
    input wire Clk,
    input wire [7:0] data,
    output wire [BOARDS*8-1:0] outputs
);

reg [7:0] regs [0:BOARDS-1];


assign  outputs = { regs[15],  regs[14],  regs[13],  regs[12],  
                regs[11],  regs[10],  regs[9],   regs[8],   
                regs[7],   regs[6],   regs[5],   regs[4], 
                regs[3],   regs[2],   regs[1],   regs[0]};    


always @(posedge Clk) begin
    if (ReadEnable)
        regs[reg_num] <= data;
end

endmodule
