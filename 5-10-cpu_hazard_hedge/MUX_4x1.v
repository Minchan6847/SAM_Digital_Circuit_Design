module MUX_4x1 #(
    parameter SIZE = 32
) (
    input [SIZE-1:0] A0,
    input [SIZE-1:0] A1,
    input [SIZE-1:0] A2,
    input [SIZE-1:0] A3,
    input [1:0] sel,
    output reg [SIZE-1:0] F
);

    always @(*) begin
        case (sel)
            2'b00:   F = A0;
            2'b01:   F = A1;
            2'b10:   F = A2;
            2'b11:   F = A3;
            default: F = {SIZE{1'b0}};
        endcase
    end

endmodule
