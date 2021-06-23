module mux_2w 
#(
    parameter WIDTH=1
)(
    input [WIDTH-1:0] d0, d1,
    input sel,
    output [WIDTH-1:0] y
);

assign y = sel ? d1 : d0;

endmodule


module mux_4w 
#(
    parameter WIDTH=1
)(
    input [WIDTH-1:0] d0, d1, d2, d3,
    input [1:0] sel,
    output wire [WIDTH-1:0] y
);

assign y = (sel == 2'b00) ? d0:
        (sel == 2'b01) ? d1:
        (sel == 2'b10) ? d2: d3;

endmodule


module demux_16w
#(parameter WIDTH=1
)(
    input wire [WIDTH-1:0] data,
    input wire [3:0] sel,
    output reg [WIDTH-1:0] d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14 ,d15
);


always @(*)
    {d15, d14, d13, d12, d11, d10, d9, d8, d7, d6, d5, d4, d3, d2, d1, d0} = data << sel;

endmodule

module demux_8w
#(parameter WIDTH=1
)(
    input wire [WIDTH-1:0] data,
    input wire [2:0] sel,
    output wire [WIDTH-1:0] d0, d1, d2, d3, d4, d5, d6, d7
);

endmodule


module mux_8w 
#(
    parameter DATA_WIDTH = 8
)(
    input [DATA_WIDTH-1:0] d0, d1, d2, d3, d4, d5, d6, d7,
    input [3:0] sel,
    output [DATA_WIDTH-1:0] y
);

assign y = (sel == 3'b000) ? d0:
        (sel == 3'b001) ? d1:
        (sel == 3'b010) ? d2:
        (sel == 3'b011) ? d3:
        (sel == 3'b100) ? d4:
        (sel == 3'b101) ? d5:
        (sel == 3'b110) ? d6: d7;


endmodule

module mux_3b_9w (
    input [2:0] d0, d1, d2, d3, d4, d5, d6, d7, d8,
    input [3:0] sel,
    output [2:0] y
);

assign y = (sel == 4'b0000) ? d0:
        (sel == 4'b0001) ? d1:
        (sel == 4'b0010) ? d2:
        (sel == 4'b0011) ? d3:
        (sel == 4'b0100) ? d4:
        (sel == 4'b0101) ? d5:
        (sel == 4'b0110) ? d6:
        (sel == 4'b0111) ? d7:
        (sel == 4'b1000) ? d8: 3'b000;

endmodule

module mux_8b_5w (
    input [7:0] d0, d1, d2, d3, d4, 
    input [2:0] sel,
    output [7:0] y
);

assign y = (sel == 3'b000) ? d0:
        (sel == 3'b001) ? d1:
        (sel == 3'b010) ? d2:
        (sel == 3'b011) ? d3:
        (sel == 3'b100) ? d4: 8'b0000000;

endmodule

  
module bn_mux_n_1_generate 
#( parameter  DATA_WIDTH = 8,
   parameter  SEL_WIDTH   = 2) 
(
    input   [((2**SEL_WIDTH)*DATA_WIDTH)-1:0] data,
    input   [SEL_WIDTH-1:0]                   sel,   
    output  [DATA_WIDTH-1:0]                  y
);

wire    [DATA_WIDTH-1:0] tmp_array [0:(2**SEL_WIDTH)-1];

genvar i;
generate
    for(i=0; i<2**SEL_WIDTH; i=i+1) 
    begin: gen_array
        assign  tmp_array[i] = data[((i+1)*DATA_WIDTH)-1:(i*DATA_WIDTH)];
    end
endgenerate

    assign  y =  tmp_array[sel];

endmodule

module bn_selector_n_1_generate 
#( parameter  DATA_WIDTH = 8,
   parameter  INPUT_CHANNELS   = 2) 
(
    input   [(INPUT_CHANNELS*DATA_WIDTH)-1:0] data,
    input   [INPUT_CHANNELS-1:0]              sel,   
    output  [DATA_WIDTH-1:0]                  y
);

genvar i;
generate
    for(i=0;i<INPUT_CHANNELS;i=i+1) 
    begin: gen_array
        assign y = sel[i] ? data[((i+1)*DATA_WIDTH)-1:(i*DATA_WIDTH)] : {DATA_WIDTH{1'bx}};
    end
endgenerate

endmodule

module bn_select_16_1_case
#(parameter DATA_WIDTH=8)
(
    input   [(16*DATA_WIDTH)-1:0] data,
    input       [15:0] sel,
    output  reg [DATA_WIDTH-1:0] y
);
    
    always @(*)
        case (sel)
            16'b0000000000000001: y=data[DATA_WIDTH-1: 0];
            16'b0000000000000010: y=data[(2*DATA_WIDTH)-1: DATA_WIDTH];
            16'b0000000000000100: y=data[(3*DATA_WIDTH)-1: (2*DATA_WIDTH)];
            16'b0000000000001000: y=data[(4*DATA_WIDTH)-1: (3*DATA_WIDTH)];
            16'b0000000000010000: y=data[(5*DATA_WIDTH)-1: (4*DATA_WIDTH)];
            16'b0000000000100000: y=data[(6*DATA_WIDTH)-1: (5*DATA_WIDTH)];
            16'b0000000001000000: y=data[(7*DATA_WIDTH)-1: (6*DATA_WIDTH)];
            16'b0000000010000000: y=data[(8*DATA_WIDTH)-1: (7*DATA_WIDTH)];
            16'b0000000100000000: y=data[(9*DATA_WIDTH)-1: (8*DATA_WIDTH)];
            16'b0000001000000000: y=data[(10*DATA_WIDTH)-1: (9*DATA_WIDTH)];
            16'b0000010000000000: y=data[(11*DATA_WIDTH)-1: (10*DATA_WIDTH)];
            16'b0000100000000000: y=data[(12*DATA_WIDTH)-1: (11*DATA_WIDTH)];
            16'b0001000000000000: y=data[(13*DATA_WIDTH)-1: (12*DATA_WIDTH)];
            16'b0010000000000000: y=data[(14*DATA_WIDTH)-1: (13*DATA_WIDTH)];
            16'b0100000000000000: y=data[(15*DATA_WIDTH)-1: (14*DATA_WIDTH)];
            16'b1000000000000000: y=data[(16*DATA_WIDTH)-1: (15*DATA_WIDTH)];
            default:     y={DATA_WIDTH{1'b0}};
        endcase
    
endmodule

module demux #(
    parameter DATA_WIDTH=8,
    parameter SEL_WIDTH=4
)(
input wire [DATA_WIDTH-1:0] in,
input wire [SEL_WIDTH-1:0] sel,
output wire [((2**SEL_WIDTH)*DATA_WIDTH)-1:0] out
);

genvar i;
generate 
  for (i = 0; i < (2**SEL_WIDTH); i = i + 1)  begin : dm_out 
    assign out[((i+1)*DATA_WIDTH)-1: (i*DATA_WIDTH)] = sel==i ? in : {DATA_WIDTH{1'bZ}};
  end
endgenerate


endmodule