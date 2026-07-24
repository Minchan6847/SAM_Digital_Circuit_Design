module Extend #(
    parameter input_size  = 16,
    parameter output_size = 32
) (
    input wire [input_size-1:0] in,
    output wire [output_size-1:0] out,
    input wire [5:0] opcode
);

    // andi(opcode: 6'h0c): zero extension
    // addi, lw, sw, beq: sign extension
    assign out = (opcode == 6'h0c) 
                 ? { {(output_size - input_size){1'b0}}, in } 
                 : { {(output_size - input_size){in[input_size-1]}}, in };

endmodule
