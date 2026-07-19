module tb_CRC_16_CCITT_Parallel ();

    logic r_Init = 0;
    logic r_Clk = 0;
    logic r_DV = 0;
    logic r_Rst_n = 1'b0;  // start in reset
    logic [15:0] w_CRC, w_CRC_Reversed_Xor;
    logic [7:0] r_Data = 8'h30;
    logic [15:0] Result;
    integer ii;

    CRC_16_CCITT_Parallel UUT (
        .i_Clk(r_Clk),
        .i_Rst_n(r_Rst_n),
        .i_Init(r_Init),
        .i_DV(r_DV),
        .i_Data(r_Data),
        .o_CRC(w_CRC),
        .o_CRC_Reversed_Xor(w_CRC_Reversed_Xor)
    );

    // Clock Generator:
    always #2 r_Clk = ~r_Clk;

    initial begin
        #100 r_Rst_n <= 1'b1;  // Release Reset

        // Initialize CRC prior to sending new data.
        @(posedge r_Clk);
        r_Init <= 1'b1;
        @(posedge r_Clk);
        r_Init <= 1'b0;

        for (ii = 0; ii < 8; ii++) begin
            @(posedge r_Clk);
            r_DV   <= 1'b1;
            r_Data <= r_Data + 1;
            $display("Value of CRC is %h", w_CRC);
        end

        @(posedge r_Clk);
        r_DV <= 1'b0;
        repeat (10) @(posedge r_Clk);
        r_DV   <= 1'b1;
        r_Data <= r_Data + 1;
        $display("Value of CRC is %h", w_CRC);
        @(posedge r_Clk);
        r_DV <= 1'b0;
        @(posedge r_Clk);
        @(posedge r_Clk);
        $display("Final value of CRC is %h", w_CRC);


        // Initialize CRC prior to sending new data.
        @(posedge r_Clk);
        r_Init <= 1'b1;
        @(posedge r_Clk);
        r_Init <= 1'b0;

        // Send Reversed 0x45 0x53
        @(posedge r_Clk);
        r_DV   <= 1'b1;
        r_Data <= ReverseBits(8'h45);
        @(posedge r_Clk);
        r_DV   <= 1'b1;
        r_Data <= ReverseBits(8'h53);
        @(posedge r_Clk);
        r_DV <= 1'b0;
        @(posedge r_Clk);

        $display("Be 0x5787 Please: %h", w_CRC_Reversed_Xor);

    end

    function [7:0] ReverseBits(input logic [7:0] data);
        automatic logic [7:0] temp = data, ii = 0;
        for (ii = 0; ii < 8; ii = ii + 1) begin
            temp[ii] = data[7-ii];
        end
        return temp;
    endfunction  // ReverseBits

    initial #300 $finish;

endmodule
