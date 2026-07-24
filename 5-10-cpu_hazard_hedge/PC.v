module PC #(
    parameter SIZE = 32
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire [SIZE-1:0] in,
    input  wire            PCWrite,
    output reg  [SIZE-1:0] out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out <= {SIZE{1'b0}};
        end else if (PCWrite) begin
            out <= in;
        end
    end

endmodule
