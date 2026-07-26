module async_fifo #(
    parameter int unsigned DEPTH = 8,
    parameter int unsigned WIDTH = 8
) (
    input logic rstn,

    // Write-clock domain
    input  logic             wclk,
    input  logic             push,
    input  logic [WIDTH-1:0] din,
    output logic             full,

    // Read-clock domain
    input  logic             rclk,
    input  logic             pop,
    output logic [WIDTH-1:0] dout,
    output logic             empty
);

    // Gray-pointer asynchronous FIFOs require a power-of-two depth.
    localparam int unsigned ADDR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam int unsigned PTR_W = ADDR_W + 1;

    logic [WIDTH-1:0] mem[0:DEPTH-1];

    logic [PTR_W-1:0] wbin, wbin_next;
    logic [PTR_W-1:0] wgray, wgray_next;
    logic [PTR_W-1:0] rbin, rbin_next;
    logic [PTR_W-1:0] rgray, rgray_next;

    (* async_reg = "true" *) logic [PTR_W-1:0] rgray_meta_wclk;
    (* async_reg = "true" *) logic [PTR_W-1:0] rgray_sync_wclk;
    (* async_reg = "true" *) logic [PTR_W-1:0] wgray_meta_rclk;
    (* async_reg = "true" *) logic [PTR_W-1:0] wgray_sync_rclk;

    // Async-assert, sync-deassert reset release for each clock domain.
    (* async_reg = "true" *) logic [1:0] wrst_pipe;
    (* async_reg = "true" *) logic [1:0] rrst_pipe;
    logic wrstn;
    logic rrstn;

    logic full_next;
    logic empty_next;
    logic write_fire;
    logic read_fire;

    // In Gray code, full is detected by inverting the two most-significant
    // synchronized read-pointer bits and comparing against the next write pointer.
    localparam logic [PTR_W-1:0] FULL_COMPARE_MASK = {2'b11, {(PTR_W - 2) {1'b0}}};

    function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] bin);
        return (bin >> 1) ^ bin;
    endfunction

    always_ff @(posedge wclk or negedge rstn) begin
        if (!rstn) begin
            wrst_pipe <= '0;
        end else begin
            wrst_pipe <= {wrst_pipe[0], 1'b1};
        end
    end

    always_ff @(posedge rclk or negedge rstn) begin
        if (!rstn) begin
            rrst_pipe <= '0;
        end else begin
            rrst_pipe <= {rrst_pipe[0], 1'b1};
        end
    end

    assign wrstn = wrst_pipe[1];
    assign rrstn = rrst_pipe[1];

    assign write_fire = push && !full;
    assign read_fire = pop && !empty;

    always_comb begin
        wbin_next  = wbin + write_fire;
        wgray_next = bin2gray(wbin_next);
        full_next  = (wgray_next == (rgray_sync_wclk ^ FULL_COMPARE_MASK));
    end

    always_comb begin
        rbin_next  = rbin + read_fire;
        rgray_next = bin2gray(rbin_next);
        empty_next = (rgray_next == wgray_sync_rclk);
    end

    // Write pointer, memory write, and write-domain full flag.
    always_ff @(posedge wclk or negedge wrstn) begin
        if (!wrstn) begin
            wbin  <= '0;
            wgray <= '0;
            full  <= 1'b0;
        end else begin
            if (write_fire) begin
                mem[wbin[ADDR_W-1:0]] <= din;
            end

            wbin  <= wbin_next;
            wgray <= wgray_next;
            full  <= full_next;
        end
    end

    // Synchronize the Gray-coded read pointer into the write domain.
    always_ff @(posedge wclk or negedge wrstn) begin
        if (!wrstn) begin
            rgray_meta_wclk <= '0;
            rgray_sync_wclk <= '0;
        end else begin
            rgray_meta_wclk <= rgray;
            rgray_sync_wclk <= rgray_meta_wclk;
        end
    end

    // Read pointer and read-domain empty flag.
    always_ff @(posedge rclk or negedge rrstn) begin
        if (!rrstn) begin
            rbin  <= '0;
            rgray <= '0;
            empty <= 1'b1;
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
            empty <= empty_next;
        end
    end

    // Synchronize the Gray-coded write pointer into the read domain.
    always_ff @(posedge rclk or negedge rrstn) begin
        if (!rrstn) begin
            wgray_meta_rclk <= '0;
            wgray_sync_rclk <= '0;
        end else begin
            wgray_meta_rclk <= wgray;
            wgray_sync_rclk <= wgray_meta_rclk;
        end
    end

    // First-word fall-through/asynchronous-read output.
    assign dout = empty ? '0 : mem[rbin[ADDR_W-1:0]];

    initial begin
        if (DEPTH < 2) $fatal(1, "DEPTH must be at least 2");
        if ((DEPTH & (DEPTH - 1)) != 0) $fatal(1, "DEPTH must be a power of two");
        if (WIDTH < 1) $fatal(1, "WIDTH must be at least 1");
    end

endmodule
