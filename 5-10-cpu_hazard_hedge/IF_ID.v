module IF_ID (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        IFID_Write,
    input  wire        IF_Flush,
    input  wire [31:0] pcAdd4_IF,
    input  wire [31:0] inst_IF,
    output reg  [31:0] pcAdd4_ID,
    output reg  [31:0] inst_ID
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcAdd4_ID <= 32'd0;
            inst_ID   <= 32'd0;
        end else if (IF_Flush) begin
            pcAdd4_ID <= 32'd0;
            inst_ID   <= 32'd0;
        end else if (IFID_Write) begin
            pcAdd4_ID <= pcAdd4_IF;
            inst_ID   <= inst_IF;
        end
        // else: 기존 값 유지
    end

endmodule
