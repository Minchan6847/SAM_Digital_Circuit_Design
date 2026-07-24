module Branch_Detection (
    input Branch,
    input equal,
    input Hazard,
    input Jump,
    input [5:0] opcode,
    output reg isBranch,
    output reg IF_Flush
);

    always @(*) begin
        isBranch = 1'b0;
        IF_Flush = 1'b0;

        if (!Hazard) begin
            if (Jump) begin
                IF_Flush = 1'b1;
            end else if (Branch) begin
                // opcode == 6'h04: beq
                // opcode == 6'h05: bne
                if ((opcode == 6'h04 && equal) || (opcode == 6'h05 && !equal)) begin
                    isBranch = 1'b1;
                    IF_Flush = 1'b1;
                end
            end
        end
    end

endmodule
