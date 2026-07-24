module Forwarding (
    input [4:0] Rs_EX,
    input [4:0] Rt_EX,
    input [4:0] Dst_MEM,
    input [4:0] Dst_WB,

    input RegWrite_MEM,
    input RegWrite_WB,

    output reg [1:0] ForwardA,
    output reg [1:0] ForwardB
);

    always @(*) begin
        // 기본값: forwarding 없음
        ForwardA = 2'b00;
        ForwardB = 2'b00;

        // ALU input A forwarding
        if (RegWrite_MEM && (Dst_MEM != 5'd0) && (Dst_MEM == Rs_EX)) begin
            ForwardA = 2'b10;
        end else if (RegWrite_WB && (Dst_WB != 5'd0) && (Dst_WB == Rs_EX)) begin
            ForwardA = 2'b01;
        end

        // ALU input B forwarding
        if (RegWrite_MEM && (Dst_MEM != 5'd0) && (Dst_MEM == Rt_EX)) begin
            ForwardB = 2'b10;
        end else if (RegWrite_WB && (Dst_WB != 5'd0) && (Dst_WB == Rt_EX)) begin
            ForwardB = 2'b01;
        end
    end

endmodule
