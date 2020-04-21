module ZeroDetector(
    input [11:0] Data,
    output Zero
);

assign Zero = ~(Data[11] | Data[10] | Data[9] | Data[8] |
                Data[7] | Data[6] | Data[5] | Data[4] |
                Data[3] | Data[2] | Data[1] | Data[0] );

endmodule