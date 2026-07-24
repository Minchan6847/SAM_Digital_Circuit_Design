module Hazard_Detection (
    input wire Branch,
    input wire MemRead_EX,
    input wire RegWrite_EX,
    input wire RegWrite_MEM,

    input wire uses_rs_ID,
    input wire uses_rt_ID,

    input wire [4:0] Rs_ID,
    input wire [4:0] Rt_ID,
    input wire [4:0] Rt_EX,
    input wire [4:0] Dst_EX,
    input wire [4:0] Dst_MEM,
    output reg IFID_Write,
    output reg Hazard,
    output reg PC_Write
);

    always @(*) begin
        IFID_Write = 1'b1;
        Hazard     = 1'b0;
        PC_Write   = 1'b1;

        // Load-use hazard
        if (MemRead_EX && (Rt_EX != 5'd0) &&
            ((uses_rs_ID && (Rt_EX == Rs_ID)) ||
             (uses_rt_ID && (Rt_EX == Rt_ID)) )
        ) begin
            IFID_Write = 1'b0;
            Hazard     = 1'b1;
            PC_Write   = 1'b0;
        end else if (Branch) begin  // Branch dependency
            if (RegWrite_EX && (Dst_EX != 5'd0) && ((Dst_EX == Rs_ID) || (Dst_EX == Rt_ID))) begin
                IFID_Write = 1'b0;
                Hazard     = 1'b1;
                PC_Write   = 1'b0;
            end
            else if (RegWrite_MEM && (Dst_MEM != 5'd0) && (Dst_MEM == Rs_ID || Dst_MEM == Rt_ID) ) begin
                IFID_Write = 1'b0;
                Hazard     = 1'b1;
                PC_Write   = 1'b0;
            end
        end

    end

endmodule
