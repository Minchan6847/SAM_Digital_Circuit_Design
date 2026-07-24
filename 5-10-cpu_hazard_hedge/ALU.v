module ALU #(
    parameter SIZE = 32
) (
    input  wire [SIZE-1:0] A,
    input  wire [SIZE-1:0] B,
    input  wire [     3:0] alu_control,
    output wire            zero,
    output reg  [SIZE-1:0] result
);

    // -------------------------------------------------------------------------
    // Control Opcode Definitions (가독성 및 유지보수를 위한 Localparam 정의)
    // -------------------------------------------------------------------------
    localparam ALU_AND = 4'b0000,
               ALU_OR  = 4'b0001,
               ALU_ADD = 4'b0010,
               ALU_SUB = 4'b0110,
               ALU_SLT = 4'b0111,
               ALU_NOR = 4'b1100;

    // -------------------------------------------------------------------------
    // Zero Flag Generator
    // -------------------------------------------------------------------------
    assign zero = (result == {SIZE{1'b0}});

    // -------------------------------------------------------------------------
    // ALU Control Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        case (alu_control)
            ALU_AND: result = A & B;
            ALU_OR:  result = A | B;
            ALU_ADD: result = A + B;
            ALU_SUB: result = A - B;
            ALU_SLT: result = ($signed(A) < $signed(B)) ? {{SIZE - 1{1'b0}}, 1'b1} : {SIZE{1'b0}};
            ALU_NOR: result = ~(A | B);
            default: result = {SIZE{1'b0}};
        endcase
    end

endmodule
