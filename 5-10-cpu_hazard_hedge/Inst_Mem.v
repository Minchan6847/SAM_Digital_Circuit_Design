module Inst_Mem #(
    parameter data_size = 32,
    parameter mem_size  = 100
) (
    input  wire [data_size-1:0] R_addr,
    output wire [data_size-1:0] inst
);

    reg [data_size-1:0] memory[0:mem_size-1];

    assign inst = memory[R_addr>>2];

endmodule
