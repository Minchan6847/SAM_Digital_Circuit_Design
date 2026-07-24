module ALU_control (
    input      [1:0] ALUOp,
    input      [5:0] funct,
    output reg [3:0] alu_control
);

    always @(*) begin
        // 안전한 기본값
        alu_control = 4'b0000;

        case (ALUOp)
            2'b00: begin
                // lw, sw, addi
                // 주소 계산 또는 덧셈
                alu_control = 4'b0010;  // ADD
            end

            2'b01: begin
                // beq, bne
                // 두 레지스터 값을 빼서 비교
                alu_control = 4'b0110;  // SUB
            end

            2'b10: begin
                // R-type: funct 필드로 실제 ALU 연산 결정
                case (funct)
                    6'h20: alu_control = 4'b0010;  // add: rd = rs + rt
                    6'h22: alu_control = 4'b0110;  // sub: rd = rs - rt
                    6'h24: alu_control = 4'b0000;  // and: rd = rs & rt
                    6'h25: alu_control = 4'b0001;  // or : rd = rs | rt
                    6'h2A: alu_control = 4'b0111;  // slt: rd = ($signed(rs) < $signed(rt))

                    default: begin
                        // 지원하지 않는 R-type funct
                        // Control에서 RegWrite=0으로 막으므로
                        // ALU 결과는 CPU 상태에 반영되지 않음
                        alu_control = 4'b0000;
                    end
                endcase
            end

            2'b11: begin
                // andi
                alu_control = 4'b0000;  // AND
            end

            default: begin
                // ALUOp가 X 또는 잘못된 값일 때 안전한 기본값
                alu_control = 4'b0000;
            end
        endcase
    end

endmodule
