module Dekatron(Step, Reverse, Rst_n, Set, In, Out);
    //Each Step cause +1 or -1(if Reverse) or storing In value(if Set)
    input wire Step;
    input wire Reverse;//1 for reverse
    input wire Rst_n;
    input wire Set;
    input wire [9:0] In; 
    output reg[9:0] Out;

always @(posedge Step or negedge Rst_n)
    if (!Rst_n)
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
                    if (Reverse) 
					begin 
                        Out <= {Out[9], Out[8:0]};
                    end 
                    else 
                    begin 
                        Out <= {Out[8:0], Out[9]};
                    end 
                end
        end
endmodule