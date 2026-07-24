module Reg_File #(
    parameter DATA_SIZE     = 32,
    parameter REG_ADDR_SIZE = 5
) (
    input wire clk,

    // Read Ports
    input  wire [REG_ADDR_SIZE-1:0] R_reg1,
    input  wire [REG_ADDR_SIZE-1:0] R_reg2,
    output wire [    DATA_SIZE-1:0] R_data1,
    output wire [    DATA_SIZE-1:0] R_data2,

    // Write Port
    input wire                     RegWrite,
    input wire [REG_ADDR_SIZE-1:0] W_reg,
    input wire [    DATA_SIZE-1:0] W_data
);

    // 주소 비트 폭(REG_ADDR_SIZE)에 맞춰 레지스터 개수를 자동 계산 (2^REG_ADDR_SIZE)
    localparam NUM_REGS = 1 << REG_ADDR_SIZE;

    // Register Array 선언
    reg [DATA_SIZE-1:0] register[0:NUM_REGS-1];

    wire zero_write;
    wire bypass_read1;
    wire bypass_read2;

    // r0에 접근하는 경우를 체크 (r0은 항상 0이므로 쓰기 금지)
    assign zero_write   = (W_reg == {REG_ADDR_SIZE{1'b0}});

    // WB에서 쓰려는 레지스터를 ID가 동시에 읽는지 검사
    assign bypass_read1 = RegWrite && !zero_write && (W_reg == R_reg1);
    assign bypass_read2 = RegWrite && !zero_write && (W_reg == R_reg2);

    // -------------------------------------------------------------------------
    // Register Write Logic (Posedge Clock)
    // -------------------------------------------------------------------------
    // 모든 순차회로를 posedge로 통일
    always @(posedge clk) begin
        if (RegWrite && !zero_write) begin
            register[W_reg] <= W_data;
        end
    end

    // -------------------------------------------------------------------------
    // Register Read Logic (Combinational)
    // -------------------------------------------------------------------------
    // r0 우선, 그다음 WB bypass, 마지막으로 register array
    assign R_data1 =
        (R_reg1 == {REG_ADDR_SIZE{1'b0}}) ?
                        {DATA_SIZE{1'b0}} : (bypass_read1 ? W_data : register[R_reg1]);

    assign R_data2 =
        (R_reg2 == {REG_ADDR_SIZE{1'b0}}) ?
                        {DATA_SIZE{1'b0}} : (bypass_read2 ? W_data : register[R_reg2]);
endmodule
