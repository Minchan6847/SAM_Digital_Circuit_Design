module ID_EX (
    input wire clk,
    input wire rst_n,
    input wire Hazard,

    input wire [1:0] ALUOp_ID,
    input wire       RegDst_ID,
    input wire       ALUSrc_ID,
    input wire       MemRead_ID,
    input wire       MemWrite_ID,
    input wire       MemtoReg_ID,
    input wire       RegWrite_ID,

    input wire [31:0] regReadData1_ID,
    input wire [31:0] regReadData2_ID,
    input wire [31:0] immExtend_ID,
    input wire [ 4:0] Rs_ID,
    input wire [ 4:0] Rt_ID,
    input wire [ 4:0] Rd_ID,

    output reg [1:0] ALUOp_EX,
    output reg       RegDst_EX,
    output reg       ALUSrc_EX,
    output reg       MemRead_EX,
    output reg       MemWrite_EX,
    output reg       MemtoReg_EX,
    output reg       RegWrite_EX,

    output reg [31:0] regReadData1_EX,
    output reg [31:0] regReadData2_EX,
    output reg [31:0] immExtend_EX,
    output reg [ 4:0] Rs_EX,
    output reg [ 4:0] Rt_EX,
    output reg [ 4:0] Rd_EX
);

    // -------------------------------------------------------------------------
    // Control registers
    // Reset과 hazard bubble에서 모두 0으로 만든다.
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ALUOp_EX    <= 2'b00;
            RegDst_EX   <= 1'b0;
            ALUSrc_EX   <= 1'b0;
            MemRead_EX  <= 1'b0;
            MemWrite_EX <= 1'b0;
            MemtoReg_EX <= 1'b0;
            RegWrite_EX <= 1'b0;
        end else if (Hazard) begin
            // ID/EX에 bubble 삽입
            ALUOp_EX    <= 2'b00;
            RegDst_EX   <= 1'b0;
            ALUSrc_EX   <= 1'b0;
            MemRead_EX  <= 1'b0;
            MemWrite_EX <= 1'b0;
            MemtoReg_EX <= 1'b0;
            RegWrite_EX <= 1'b0;
        end else begin
            ALUOp_EX    <= ALUOp_ID;
            RegDst_EX   <= RegDst_ID;
            ALUSrc_EX   <= ALUSrc_ID;
            MemRead_EX  <= MemRead_ID;
            MemWrite_EX <= MemWrite_ID;
            MemtoReg_EX <= MemtoReg_ID;
            RegWrite_EX <= RegWrite_ID;
        end
    end

    // -------------------------------------------------------------------------
    // Data registers
    // Reset하지 않는다. Hazard 때 값이 무엇인지는 상관없다.
    // 위 control 신호가 0이므로 architectural side effect가 발생하지 않는다.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        regReadData1_EX <= regReadData1_ID;
        regReadData2_EX <= regReadData2_ID;
        immExtend_EX    <= immExtend_ID;
        Rs_EX           <= Rs_ID;
        Rt_EX           <= Rt_ID;
        Rd_EX           <= Rd_ID;
    end

endmodule
