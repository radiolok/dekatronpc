module Dekatron(StepIn, Dir, Rst, Out, StepOut);
    input wire Step;
    input wire Dir;//1 for reverse
    input wire Rst;
    inout Reg[9:0] Out;
    output wire StepOut;

always @(posedge StepIn, negedge Rst)
    if (!Rst)
        begin
            Out <= 10'b1;
            assign StepOut = 1'b0;
        end
    else
        begin
            if (!Dir) 
            begin 
                Out <= {Out[8:0], Out[9]};
                assign StepOut = Out[0];
            end 
            else 
            begin 
                Out <= {Out[9], Out[8:0]};
                assign StepOut = Out[9];
            end 
        end

endmodule