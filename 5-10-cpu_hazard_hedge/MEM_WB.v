module MEM_WB (
    input wire clk,
    input wire rst_n,

    input wire        MemtoReg_MEM,
    input wire        RegWrite_MEM,
    input wire [31:0] dmReadData_MEM,
    input wire [31:0] ALUResult_MEM,
    input wire [ 4:0] Dst_MEM,

    output reg        MemtoReg_WB,
    output reg        RegWrite_WB,
    output reg [31:0] dmReadData_WB,
    output reg [31:0] ALUResult_WB,
    output reg [ 4:0] Dst_WB
);

    // -------------------------------------------------------------------------
    // Control registers
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MemtoReg_WB <= 1'b0;
            RegWrite_WB <= 1'b0;
        end else begin
            MemtoReg_WB <= MemtoReg_MEM;
            RegWrite_WB <= RegWrite_MEM;
        end
    end

    // -------------------------------------------------------------------------
    // Data registers: reset 없음
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        dmReadData_WB <= dmReadData_MEM;
        ALUResult_WB  <= ALUResult_MEM;
        Dst_WB        <= Dst_MEM;
    end

endmodule
