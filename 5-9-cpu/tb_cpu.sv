`timescale 1ns / 1ps

module tb_cpu;
    logic clk;
    logic rstn;
    int   error_count;

    cpu u_cpu (
        .clk (clk),
        .rstn(rstn)
    );

    // 10 ns clock period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Deassert reset away from the active clock edge to avoid a race.
    initial begin
        rstn = 1'b0;
        repeat (3) @(negedge clk);
        rstn = 1'b1;
    end

    task automatic check_reg(input int unsigned index, input logic [31:0] expected);
        logic [31:0] actual;
        begin
            actual = u_cpu.u1_RegFile.array[index];
            assert (actual === expected)
            else begin
                $error("REG FAIL: r%0d expected=%0d (0x%08h), actual=%0d (0x%08h)", index,
                       expected, expected, actual, actual);
                error_count++;
            end
        end
    endtask

    task automatic check_mem(input int unsigned index, input logic [31:0] expected);
        logic [31:0] actual;
        begin
            actual = u_cpu.u3_DataMem.mem[index];
            assert (actual === expected)
            else begin
                $error("MEM FAIL: mem[%0d] expected=%0d (0x%08h), actual=%0d (0x%08h)", index,
                       expected, expected, actual, actual);
                error_count++;
            end
        end
    endtask

    // Architectural invariant: r0 must always remain zero.
    always @(posedge clk) begin
        if (rstn) begin
            assert (u_cpu.u1_RegFile.array[0] === 32'd0)
            else begin
                $error("r0 was modified: actual=0x%08h", u_cpu.u1_RegFile.array[0]);
                error_count++;
            end
        end
    end

    // The current CPU only supports aligned word accesses.
    always @(posedge clk) begin
        if (rstn && (u_cpu.MemReadMEM || u_cpu.MemWriteMEM)) begin
            assert (u_cpu.ALUResultMEM[1:0] === 2'b00)
            else begin
                $error("Unaligned memory access: address=0x%08h", u_cpu.ALUResultMEM);
                error_count++;
            end

            assert (u_cpu.ALUResultMEM <= 32'd508)
            else begin
                $error("Out-of-range data-memory access: address=0x%08h", u_cpu.ALUResultMEM);
                error_count++;
            end
        end
    end

    initial begin
        error_count = 0;

        wait (rstn === 1'b1);

        // The last load (lw r12, 12(r0)) has reached WB by this point.
        // Extra cycles also allow the taken branch to begin the next loop.
        repeat (25) @(posedge clk);
        #1;

        // Register-file expectations
        check_reg(0, 32'd0);
        check_reg(1, 32'd1);
        check_reg(2, 32'd2);
        check_reg(3, 32'd3);
        check_reg(4, 32'd4);
        check_reg(5, 32'd1);
        check_reg(6, 32'd3);
        check_reg(7, 32'd5);
        check_reg(8, 32'd7);
        check_reg(9, 32'd1);
        check_reg(10, 32'd3);
        check_reg(11, 32'd5);
        check_reg(12, 32'd7);

        // DataMem is word-organized internally.
        // Byte addresses 0, 4, 8, and 12 map to mem[0], mem[1], mem[2], mem[3].
        check_mem(0, 32'd1);
        check_mem(1, 32'd3);
        check_mem(2, 32'd5);
        check_mem(3, 32'd7);

        if (error_count == 0) begin
            $display("PASS: CPU register and data-memory results are correct.");
            $finish;
        end else begin
            $fatal(1, "FAIL: %0d assertion/check error(s) detected.", error_count);
        end
    end

    // Prevent an endless simulation if the design stops progressing.
    initial begin
        #2000;
        $fatal(1, "TIMEOUT: CPU test did not finish.");
    end

endmodule
