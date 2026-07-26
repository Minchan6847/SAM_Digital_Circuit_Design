`timescale 1ns / 1ps

module tb_async_fifo;
    localparam int unsigned DEPTH = 8;
    localparam int unsigned WIDTH = 8;
    localparam int unsigned RANDOM_WORDS = 48;

    logic             rstn;
    logic             wclk;
    logic             push;
    logic [WIDTH-1:0] din;
    logic             full;

    logic             rclk;
    logic             pop;
    logic [WIDTH-1:0] dout;
    logic             empty;

    logic [WIDTH-1:0] model_q          [$];
    int               error_count;
    int               accepted_writes;
    int               accepted_reads;
    bit               checking_enabled;

    async_fifo #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH)
    ) dut (
        .rstn (rstn),
        .wclk (wclk),
        .push (push),
        .din  (din),
        .full (full),
        .rclk (rclk),
        .pop  (pop),
        .dout (dout),
        .empty(empty)
    );

    // Positive edges never coincide: 4+8n cannot equal 5+10m.
    initial begin
        wclk = 1'b0;
        forever #4 wclk = ~wclk;
    end

    initial begin
        rclk = 1'b0;
        forever #5 rclk = ~rclk;
    end

    // Record every write actually accepted by the DUT.
    always @(posedge wclk) begin
        if (checking_enabled && push && !full) begin
            model_q.push_back(din);
            accepted_writes++;
        end
    end

    // Check every read actually accepted by the DUT.
    always @(posedge rclk) begin
        logic [WIDTH-1:0] expected;

        if (checking_enabled && pop && !empty) begin
            if (model_q.size() == 0) begin
                $error("Read accepted while reference queue is empty at %0t", $time);
                error_count++;
            end else begin
                expected = model_q.pop_front();
                if (dout !== expected) begin
                    $error("Data mismatch at %0t: expected=%0h actual=%0h", $time, expected, dout);
                    error_count++;
                end
            end
            accepted_reads++;
        end
    end

    task automatic write_word(input logic [WIDTH-1:0] data_i);
        bit accepted;
        begin
            accepted = 1'b0;
            @(negedge wclk);
            din  = data_i;
            push = 1'b1;

            while (!accepted) begin
                @(posedge wclk);
                accepted = !full;
            end

            @(negedge wclk);
            push = 1'b0;
        end
    endtask

    task automatic read_word;
        bit accepted;
        begin
            accepted = 1'b0;
            @(negedge rclk);
            pop = 1'b1;

            while (!accepted) begin
                @(posedge rclk);
                accepted = !empty;
            end

            @(negedge rclk);
            pop = 1'b0;
        end
    endtask

    task automatic expect_full(input logic expected);
        #1;
        if (full !== expected) begin
            $error("full mismatch at %0t: expected=%0b actual=%0b", $time, expected, full);
            error_count++;
        end
    endtask

    task automatic expect_empty(input logic expected);
        #1;
        if (empty !== expected) begin
            $error("empty mismatch at %0t: expected=%0b actual=%0b", $time, expected, empty);
            error_count++;
        end
    endtask

    initial begin : test_sequence
        int before_count;

        rstn             = 1'b0;
        push             = 1'b0;
        pop              = 1'b0;
        din              = '0;
        error_count      = 0;
        accepted_writes  = 0;
        accepted_reads   = 0;
        checking_enabled = 1'b0;

        //---- Stage 1 ----//
        // Release reset away from both active clock edges. The DUT then
        // synchronizes reset deassertion independently into each domain.
        #37 rstn = 1'b1;
        repeat (4) @(posedge wclk);
        repeat (4) @(posedge rclk);
        checking_enabled = 1'b1;

        expect_full(1'b0);
        expect_empty(1'b1);

        //---- Stage 2 ----//
        // Fill the FIFO exactly to capacity.
        for (int i = 0; i < DEPTH; i++) write_word(8'h10 + i);

        expect_full(1'b1);

        //---- Stage 3 ----//
        // A write while full must be rejected.
        before_count = accepted_writes;
        @(negedge wclk);
        din  = 8'hEE;
        push = 1'b1;
        repeat (3) @(posedge wclk);
        @(negedge wclk);
        push = 1'b0;

        if (accepted_writes != before_count) begin
            $error("Write was accepted while full");
            error_count++;
        end

        //---- Stage 4 ----//
        // Pop one word and hold a write request until the synchronized
        // read pointer causes full to deassert in the write domain.
        fork
            read_word();
            write_word(8'h80);
        join

        //---- Stage 5 ----//
        // Occupancy is still DEPTH after the read/write exchange.
        for (int i = 0; i < DEPTH; i++) read_word();

        expect_empty(1'b1);

        //---- Stage 6 ----//
        // A read while empty must be rejected.
        before_count = accepted_reads;
        @(negedge rclk);
        pop = 1'b1;
        repeat (3) @(posedge rclk);
        @(negedge rclk);
        pop = 1'b0;

        if (accepted_reads != before_count) begin
            $error("Read was accepted while empty");
            error_count++;
        end

        //---- Stage 7 ----//
        // Concurrent randomized-rate traffic exercises pointer wraparound
        // and repeated CDC synchronization in both directions.
        fork
            begin : writer_thread
                for (int i = 0; i < RANDOM_WORDS; i++) begin
                    repeat ($urandom_range(0, 2)) @(negedge wclk);
                    write_word(8'hA0 + i);
                end
            end
            begin : reader_thread
                for (int i = 0; i < RANDOM_WORDS; i++) begin
                    repeat ($urandom_range(0, 3)) @(negedge rclk);
                    read_word();
                end
            end
        join

        //---- Stage 8 ----//
        // Termination Consistency Check

        repeat (4) @(posedge rclk);

        if (model_q.size() != 0) begin
            $error("Reference queue is not empty: %0d item(s) remain", model_q.size());
            error_count++;
        end

        if (accepted_writes != accepted_reads) begin
            $error("Accepted transaction count mismatch: writes=%0d reads=%0d", accepted_writes,
                   accepted_reads);
            error_count++;
        end

        expect_empty(1'b1);

        if (error_count == 0) $display("PASS: async_fifo completed all checks");
        else $fatal(1, "FAIL: %0d error(s) detected", error_count);

        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "TIMEOUT");
    end

endmodule
