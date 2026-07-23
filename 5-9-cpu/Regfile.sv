module RegFile (
    input clk,
    input rstn,
    input [4:0] rs,
    input [4:0] rt,
    input [4:0] WriteReg,
    input [31:0] WriteData,
    input RegWrite,
    output [31:0] ReadData1,
    output [31:0] ReadData2
);

    reg [31:0] array[31:0];

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 32; i++) begin
                array[i] <= 0;
            end
        end else if (RegWrite && (WriteReg != 5'd0)) begin
            array[WriteReg] <= WriteData;
        end
    end

    assign ReadData1 = (rs == 5'd0) ? 32'd0 : array[rs];
    assign ReadData2 = (rt == 5'd0) ? 32'd0 : array[rt];

endmodule
