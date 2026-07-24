module Control (
    input [5:0] inst_31_26,
    input [5:0] funct,

    output reg       RegDst,
    output reg       Jump,
    output reg       Branch,
    output reg       MemRead,
    output reg       MemtoReg,
    output reg [1:0] ALUOp,
    output reg       MemWrite,
    output reg       ALUSrc,
    output reg       RegWrite
);

    // This block is mainly used for designed inst.

    always @(*) begin
        RegDst   = 1'b0;
        Jump     = 1'b0;
        Branch   = 1'b0;
        MemRead  = 1'b0;
        MemtoReg = 1'b0;
        ALUOp    = 2'b00;
        MemWrite = 1'b0;
        ALUSrc   = 1'b0;
        RegWrite = 1'b0;

        case (inst_31_26)

            6'h00: begin  // R-type
                case (funct)
                    6'h20,  // add
                    6'h22,  // sub
                    6'h24,  // and
                    6'h25,  // or
                    6'h2A: begin  // slt
                        RegDst   = 1'b1;
                        RegWrite = 1'b1;
                        ALUOp    = 2'b10;
                    end

                    default: begin
                        // 지원하지 않는 R-type:
                        // 기본값이 유지되어 side effect가 없는 NOP으로 처리
                    end
                endcase
            end

            6'h08: begin  // addi
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                ALUOp    = 2'b00;
            end

            6'h0C: begin  // andi
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                ALUOp    = 2'b11;
            end

            6'h04: begin  // beq
                Branch = 1'b1;
                ALUOp  = 2'b01;
            end

            6'h05: begin  // bne
                Branch = 1'b1;
                ALUOp  = 2'b01;
            end

            6'h23: begin  // lw
                MemRead  = 1'b1;
                MemtoReg = 1'b1;
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                ALUOp    = 2'b00;
            end

            6'h2B: begin  // sw
                MemWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end

            6'h02: begin  // j
                Jump = 1'b1;
            end

            default: begin
                RegDst   = 1'b0;
                Jump     = 1'b0;
                Branch   = 1'b0;
                MemRead  = 1'b0;
                MemtoReg = 1'b0;
                ALUOp    = 2'b00;
                MemWrite = 1'b0;
                ALUSrc   = 1'b0;
                RegWrite = 1'b0;
            end

        endcase
    end

endmodule
