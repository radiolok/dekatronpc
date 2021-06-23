module Ms6205(
    input wire Rst_n,
    input wire Clk,
    output wire [7:0] address,
    output wire [7:0] data,
    input wire write_addr,
    input wire write_data,
    input wire ready,
    input wire key_ms6205_iram,
    input wire key_ms6205_dram,
    input wire key_ms6205_cin,
    input wire key_ms6205_cout,
    output reg [1:0] ms6205_currentView

);

parameter COLUMNS = 16;
parameter ROWS = 10;
parameter WIDTH = 8;

wire c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14 , c15;

assign address = 8'b00000001;

demux_16w demuxColumns
    (.data(Clk),
    .sel(address[7:4]),
    .d0(c0), .d1(c1), .d2(c2), .d3(c3),
    .d4(c4), .d5(c5), .d6(c6), .d7(c7),
    .d8(c8), .d9(c9), .d10(c10), .d11(c11),
    .d12(c12), .d13(c13), .d14(c14), .d15(c15)
    );

wire r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14 , r15;

demux_16w demuxRows
    (.data(Clk),
    .sel(address[3:0]),
    .d0(r0), .d1(r1), .d2(r2), .d3(r3),
    .d4(r4), .d5(r5), .d6(r6), .d7(r7),
    .d8(r8), .d9(r9), .d10(r10), .d11(r11),
    .d12(r12), .d13(r13), .d14(r14), .d15(r15)
    );

wire [15:0] CsRows;
assign CsRows = {r15, r14, r13, r12, r11, r10, r9, r8, r7, r6, r5, r4, r3, r2, r1, r0};

wire [(COLUMNS*WIDTH)-1 : 0] OutShared;

bn_select_16_1_case #(
    .DATA_WIDTH(WIDTH))
selOut(
        .y(data),
        .sel(CsRows),
        .data(OutShared)
);

RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column0 (.Rst_n(Rst_n),.En(c0),.Out(OutShared[WIDTH-1: 0]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column1 (.Rst_n(Rst_n),.En(c1),.Out(OutShared[(2*WIDTH)-1: WIDTH]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column2 (.Rst_n(Rst_n),.En(c2),.Out(OutShared[(3*WIDTH)-1: (2*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column3 (.Rst_n(Rst_n),.En(c3),.Out(OutShared[(4*WIDTH)-1: (3*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column4 (.Rst_n(Rst_n),.En(c4),.Out(OutShared[(5*WIDTH)-1: (4*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column5 (.Rst_n(Rst_n),.En(c5),.Out(OutShared[(6*WIDTH)-1: (5*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column6 (.Rst_n(Rst_n),.En(c6),.Out(OutShared[(7*WIDTH)-1: (6*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column7 (.Rst_n(Rst_n),.En(c7),.Out(OutShared[(8*WIDTH)-1: (7*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column8 (.Rst_n(Rst_n),.En(c8),.Out(OutShared[(9*WIDTH)-1: (8*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column9 (.Rst_n(Rst_n),.En(c9),.Out(OutShared[(10*WIDTH)-1: (9*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column10 (.Rst_n(Rst_n),.En(c10),.Out(OutShared[(11*WIDTH)-1: (10*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column11 (.Rst_n(Rst_n),.En(c11),.Out(OutShared[(12*WIDTH)-1: (11*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column12 (.Rst_n(Rst_n),.En(c12),.Out(OutShared[(13*WIDTH)-1: (12*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column13 (.Rst_n(Rst_n),.En(c13),.Out(OutShared[(14*WIDTH)-1: (13*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column14 (.Rst_n(Rst_n),.En(c14),.Out(OutShared[(15*WIDTH)-1: (14*WIDTH)]),.Cs(CsRows));
RegisterFileSharedOut #(.WIDTH(8),.HEIGHT(ROWS)) column15 (.Rst_n(Rst_n),.En(c15),.Out(OutShared[(16*WIDTH)-1: (15*WIDTH)]),.Cs(CsRows));


reg [1:0] ms6205_nextView;

parameter [1:0] 
    MS6205_IRAM = 2'b00,
    MS6205_DRAM = 2'b01,
    MS6205_CIN = 2'b10,
    MS6205_COUT = 2'b11;

always @(*) begin
        if (key_ms6205_iram)
            ms6205_nextView = MS6205_IRAM;
        else if (key_ms6205_dram)
            ms6205_nextView = MS6205_DRAM;
        else if (key_ms6205_cin)
            ms6205_nextView = MS6205_CIN;
        else if (key_ms6205_cout)
            ms6205_nextView = MS6205_COUT;
        else
            ms6205_nextView = ms6205_currentView;
end

always @(posedge Clk, negedge Rst_n) begin
    if (!Rst_n)
        ms6205_currentView <= MS6205_IRAM;
    else begin
        ms6205_currentView <= ms6205_nextView;
    end
end


endmodule