module EX_MEM (
    input wire clk,
    input wire rst_n,

    input wire        MemRead_EX,
    input wire        MemWrite_EX,
    input wire        MemtoReg_EX,
    input wire        RegWrite_EX,
    input wire [31:0] ALUResult_EX,
    input wire [31:0] ForwardBOut_EX,
    input wire [ 4:0] Dst_EX,

    output reg        MemRead_MEM,
    output reg        MemWrite_MEM,
    output reg        MemtoReg_MEM,
    output reg        RegWrite_MEM,
    output reg [31:0] ALUResult_MEM,
    output reg [31:0] ForwardBOut_MEM,
    output reg [ 4:0] Dst_MEM
);

    // -------------------------------------------------------------------------
    // Control registers
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MemRead_MEM  <= 1'b0;
            MemWrite_MEM <= 1'b0;
            MemtoReg_MEM <= 1'b0;
            RegWrite_MEM <= 1'b0;
        end else begin
            MemRead_MEM  <= MemRead_EX;
            MemWrite_MEM <= MemWrite_EX;
            MemtoReg_MEM <= MemtoReg_EX;
            RegWrite_MEM <= RegWrite_EX;
        end
    end

    // -------------------------------------------------------------------------
    // Data registers: reset 없음
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        ALUResult_MEM   <= ALUResult_EX;
        ForwardBOut_MEM <= ForwardBOut_EX;
        Dst_MEM         <= Dst_EX;
    end

endmodule
