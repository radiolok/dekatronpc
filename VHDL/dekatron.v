module Dekatron(Step, Reverse, Rst, Set, In, Out);
    input wire Step;
    input wire Reverse;//1 for reverse
    input wire Rst;
    input wire Set;
    input wire [9:0] In; 
    output reg[9:0] Out;

always @(posedge Step, negedge Rst)
    if (!Rst)
        begin
            Out <= 10'b1;
        end
    else
        begin
            if (Set)
                begin
                    Out  <= In;
                end
            else
                begin
                    if (!Dir) 
                    begin 
                        Out <= {Out[8:0], Out[9]};
                    end 
                    else 
                    begin 
                        Out <= {Out[9], Out[8:0]};
                    end 
                end
        end
endmodule
