module DataMem (
    input clk,
    input rstn,
    input MemRead,
    input MemWrite,
    input [31:0] Address,
    input [31:0] WriteData,
    output [31:0] ReadData
);
    reg [31:0] mem[127:0];

    // Byte address를 word index로 변환
    wire [6:0] word_addr = Address[8:2];

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 128; i++) begin
                mem[i] <= 32'd0;
            end
        end else if (MemWrite) begin
            mem[word_addr] <= WriteData;
        end
    end

    assign ReadData = MemRead ? mem[word_addr] : 32'd0;

endmodule
