`timescale 1ns / 1ps

module tb_sync_fifo;
    localparam int DEPTH = 4;
    localparam int WIDTH = 8;
    localparam int AF_LEVEL = 1;
    localparam int AE_LEVEL = 1;

    logic clk;
    logic rstn;
    logic push;
    logic pop;
    logic [WIDTH-1:0] din;
    wire [WIDTH-1:0] dout;
    wire full, empty, a_full, a_empty;

    logic [WIDTH-1:0] model_q[$];
    int error_count;

    sync_fifo #(
        .DEPTH   (DEPTH),
        .WIDTH   (WIDTH),
        .AF_LEVEL(AF_LEVEL),
        .AE_LEVEL(AE_LEVEL)
    ) dut (
        .clk    (clk),
        .rstn   (rstn),
        .push   (push),
        .pop    (pop),
        .din    (din),
        .dout   (dout),
        .full   (full),
        .empty  (empty),
        .a_full (a_full),
        .a_empty(a_empty)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_flags;
        int n;
        begin
            n = model_q.size();
            if (full !== (n == DEPTH)) begin
                $error("full mismatch: count=%0d full=%b", n, full);
                error_count++;
            end
            if (empty !== (n == 0)) begin
                $error("empty mismatch: count=%0d empty=%b", n, empty);
                error_count++;
            end
            if (a_full !== (n >= DEPTH - AF_LEVEL)) begin
                $error("a_full mismatch: count=%0d a_full=%b", n, a_full);
                error_count++;
            end
            if (a_empty !== (n <= AE_LEVEL)) begin
                $error("a_empty mismatch: count=%0d a_empty=%b", n, a_empty);
                error_count++;
            end
        end
    endtask

    task automatic cycle(input logic push_i, input logic pop_i, input logic [WIDTH-1:0] data_i);
        logic pop_fire_m;
        logic push_fire_m;
        logic [WIDTH-1:0] expected;
        int pre_count;
        begin
            @(negedge clk);
            push = push_i;
            pop = pop_i;
            din = data_i;

            pre_count = model_q.size();
            pop_fire_m = pop_i && (pre_count != 0);
            push_fire_m = push_i && ((pre_count != DEPTH) || pop_fire_m);

            @(posedge clk);
            if (pop_fire_m) begin
                expected = model_q.pop_front();
                if (dout !== expected) begin
                    $error("data mismatch: expected=%02h actual=%02h", expected, dout);
                    error_count++;
                end
            end

            if (push_fire_m) model_q.push_back(data_i);

            #1;
            check_flags();
        end
    endtask

    initial begin
        rstn        = 1'b0;
        push        = 1'b0;
        pop         = 1'b0;
        din         = '0;
        error_count = 0;
        model_q.delete();

        repeat (3) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        #1 check_flags();

        // Fill and flag-boundary checks.
        cycle(1, 0, 8'h10);
        cycle(1, 0, 8'h11);
        cycle(1, 0, 8'h12);
        cycle(1, 0, 8'h13);

        // Push while full must be ignored.
        cycle(1, 0, 8'hEE);

        // At full, simultaneous pop/push keeps occupancy at DEPTH.
        cycle(1, 1, 8'h14);  // pops 10, pushes 14
        cycle(0, 1, '0);  // pops 11
        cycle(0, 1, '0);  // pops 12
        cycle(0, 1, '0);  // pops 13
        cycle(0, 1, '0);  // pops 14

        // Pop while empty must be ignored.
        cycle(0, 1, '0);

        // At empty, simultaneous push/pop accepts only the push.
        cycle(1, 1, 8'h30);
        cycle(0, 1, '0);  // pops 30

        // Pointer wraparound test.
        cycle(1, 0, 8'h20);
        cycle(1, 0, 8'h21);
        cycle(1, 0, 8'h22);
        cycle(0, 1, '0);  // pops 20
        cycle(1, 0, 8'h23);
        cycle(1, 0, 8'h24);
        cycle(0, 1, '0);  // pops 21
        cycle(0, 1, '0);  // pops 22
        cycle(0, 1, '0);  // pops 23
        cycle(0, 1, '0);  // pops 24

        @(negedge clk);
        push = 1'b0;
        pop  = 1'b0;

        if (error_count == 0) $display("PASS: sync_fifo completed all checks");
        else $fatal(1, "FAIL: %0d error(s)", error_count);

        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "TIMEOUT");
    end

endmodule
