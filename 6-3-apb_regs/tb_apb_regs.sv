`timescale 1ns / 1ps

module tb_apb_regs;

    localparam int unsigned AW = 5;
    localparam int unsigned DW = 32;

    logic                 pclk;
    logic                 presetn;
    logic        [  31:0] paddr;
    logic                 penable;
    logic                 pwrite;
    logic        [DW-1:0] pwdata;
    logic                 psel_0;
    logic                 psel_1;

    logic                 pready_0;
    logic                 pslverr_0;
    logic        [DW-1:0] prdata_0;
    logic                 pready_1;
    logic                 pslverr_1;
    logic        [DW-1:0] prdata_1;

    logic        [  31:0] status32_0;
    logic        [  15:0] status16_0;
    logic        [   7:0] status8_0;
    logic        [  31:0] status32_1;
    logic        [  15:0] status16_1;
    logic        [   7:0] status8_1;

    logic        [  31:0] control32_0;
    logic        [  15:0] control16_0;
    logic        [   7:0] control8_0;
    logic        [  31:0] control32_1;
    logic        [  15:0] control16_1;
    logic        [   7:0] control8_1;

    int unsigned          error_count;

    wire                  selected_pready = psel_0 ? pready_0 : psel_1 ? pready_1 : 1'b0;

    wire                  selected_pslverr = psel_0 ? pslverr_0 : psel_1 ? pslverr_1 : 1'b0;

    wire         [DW-1:0] selected_prdata = psel_0 ? prdata_0 : psel_1 ? prdata_1 : '0;

    always #5 pclk = ~pclk;

    task automatic check_equal(input string name, input logic [DW-1:0] actual,
                               input logic [DW-1:0] expected);
        if (actual !== expected) begin
            $error("%s: actual=0x%08h expected=0x%08h", name, actual, expected);
            error_count++;
        end
    endtask

    task automatic apb_transfer(input logic write_i, input logic [31:0] addr_i,
                                input logic [DW-1:0] wdata_i, output logic [DW-1:0] rdata_o,
                                output logic error_o);
        int unsigned wait_cycles;

        /* Setup phase */
        @(negedge pclk);
        paddr   = addr_i;
        pwdata  = wdata_i;
        pwrite  = write_i;
        penable = 1'b0;
        psel_0  = (addr_i[31:AW] == 0);
        psel_1  = (addr_i[31:AW] == 1);

        if (!(psel_0 ^ psel_1)) begin
            $error("Address 0x%08h selects zero or multiple slaves", addr_i);
            error_count++;
        end

        /* Access phase */
        @(negedge pclk);
        penable = 1'b1;

        wait_cycles = 0;
        do begin
            @(posedge pclk);
            #1;
            wait_cycles++;

            if (wait_cycles > 16) begin
                $fatal(1, "APB timeout at address 0x%08h", addr_i);
            end
        end while (!selected_pready);

        rdata_o = selected_prdata;
        error_o = selected_pslverr;

        /* Idle phase */
        @(negedge pclk);
        penable = 1'b0;
        psel_0  = 1'b0;
        psel_1  = 1'b0;
        pwrite  = 1'b0;
        paddr   = '0;
        pwdata  = '0;
    endtask

    task automatic apb_write_check(input logic [31:0] addr_i, input logic [DW-1:0] data_i,
                                   input logic expected_error);
        logic [DW-1:0] unused_rdata;
        logic          actual_error;

        apb_transfer(1'b1, addr_i, data_i, unused_rdata, actual_error);

        if (actual_error !== expected_error) begin
            $error("WRITE 0x%08h: PSLVERR=%b expected=%b", addr_i, actual_error, expected_error);
            error_count++;
        end
    endtask

    task automatic apb_read_check(input logic [31:0] addr_i, input logic [DW-1:0] expected_data,
                                  input logic expected_error);
        logic [DW-1:0] actual_data;
        logic          actual_error;

        apb_transfer(1'b0, addr_i, '0, actual_data, actual_error);

        if (actual_error !== expected_error) begin
            $error("READ 0x%08h: PSLVERR=%b expected=%b", addr_i, actual_error, expected_error);
            error_count++;
        end

        if (!expected_error) begin
            check_equal($sformatf("READ 0x%08h", addr_i), actual_data, expected_data);
        end
    endtask

    initial begin
        pclk        = 1'b0;
        presetn     = 1'b0;
        paddr       = '0;
        penable     = 1'b0;
        pwrite      = 1'b0;
        pwdata      = '0;
        psel_0      = 1'b0;
        psel_1      = 1'b0;
        error_count = 0;

        status32_0  = 32'h3203_2032;
        status16_0  = 16'h1601;
        status8_0   = 8'h80;
        status32_1  = 32'h3213_2132;
        status16_1  = 16'h1611;
        status8_1   = 8'h81;

        repeat (3) @(posedge pclk);
        @(negedge pclk);
        presetn = 1'b1;

        repeat (2) @(posedge pclk);
        #1;

        check_equal("control32_0 reset", control32_0, 32'h0);
        check_equal("control16_0 reset", {16'h0, control16_0}, 32'h0);
        check_equal("control8_0 reset", {24'h0, control8_0}, 32'h0);
        check_equal("control32_1 reset", control32_1, 32'h0);
        check_equal("control16_1 reset", {16'h0, control16_1}, 32'h0);
        check_equal("control8_1 reset", {24'h0, control8_1}, 32'h0);

        /* Slave 0 register accesses */
        apb_read_check(32'h0000_0000, 32'h1234_5678, 1'b0);
        apb_write_check(32'h0000_0004, 32'hA5A5_5A5A, 1'b0);
        apb_write_check(32'h0000_0008, 32'hFFFF_1234, 1'b0);
        apb_write_check(32'h0000_000C, 32'hFFFF_FF56, 1'b0);

        apb_read_check(32'h0000_0004, 32'hA5A5_5A5A, 1'b0);
        apb_read_check(32'h0000_0008, 32'h0000_1234, 1'b0);
        apb_read_check(32'h0000_000C, 32'h0000_0056, 1'b0);
        apb_read_check(32'h0000_0014, status32_0, 1'b0);
        apb_read_check(32'h0000_0018, {16'h0, status16_0}, 1'b0);
        apb_read_check(32'h0000_001C, {24'h0, status8_0}, 1'b0);

        /* Slave 1: base address 0x20, same internal register map */
        apb_read_check(32'h0000_0020, 32'h1234_5678, 1'b0);
        apb_write_check(32'h0000_0024, 32'h1122_3344, 1'b0);
        apb_write_check(32'h0000_0028, 32'h0000_7788, 1'b0);
        apb_write_check(32'h0000_002C, 32'h0000_0099, 1'b0);

        apb_read_check(32'h0000_0024, 32'h1122_3344, 1'b0);
        apb_read_check(32'h0000_0028, 32'h0000_7788, 1'b0);
        apb_read_check(32'h0000_002C, 32'h0000_0099, 1'b0);
        apb_read_check(32'h0000_0034, status32_1, 1'b0);
        apb_read_check(32'h0000_0038, {16'h0, status16_1}, 1'b0);
        apb_read_check(32'h0000_003C, {24'h0, status8_1}, 1'b0);

        /* Read-only/reserved/unaligned accesses */
        apb_write_check(32'h0000_0000, 32'hDEAD_BEEF, 1'b1);
        apb_write_check(32'h0000_0014, 32'hDEAD_BEEF, 1'b1);
        apb_read_check(32'h0000_0010, 32'h0, 1'b1);
        apb_read_check(32'h0000_0005, 32'h0, 1'b1);

        /* Failed writes must not modify writable registers */
        apb_read_check(32'h0000_0004, 32'hA5A5_5A5A, 1'b0);

        if (error_count == 0) begin
            $display("PASS: APB register block completed all checks");
            $finish;
        end else begin
            $fatal(1, "FAIL: %0d APB check(s) failed", error_count);
        end
    end

    initial begin
        #10_000;
        $fatal(1, "TIMEOUT");
    end

    apb_regs #(
        .DW(DW),
        .AW(AW)
    ) u_apb_regs_0 (
        .pclk     (pclk),
        .presetn  (presetn),
        .paddr    (paddr[AW-1:0]),
        .psel     (psel_0),
        .penable  (penable),
        .pwrite   (pwrite),
        .pwdata   (pwdata),
        .prdata   (prdata_0),
        .pready   (pready_0),
        .pslverr  (pslverr_0),
        .status32 (status32_0),
        .status16 (status16_0),
        .status8  (status8_0),
        .control32(control32_0),
        .control16(control16_0),
        .control8 (control8_0)
    );

    apb_regs #(
        .DW(DW),
        .AW(AW)
    ) u_apb_regs_1 (
        .pclk     (pclk),
        .presetn  (presetn),
        .paddr    (paddr[AW-1:0]),
        .psel     (psel_1),
        .penable  (penable),
        .pwrite   (pwrite),
        .pwdata   (pwdata),
        .prdata   (prdata_1),
        .pready   (pready_1),
        .pslverr  (pslverr_1),
        .status32 (status32_1),
        .status16 (status16_1),
        .status8  (status8_1),
        .control32(control32_1),
        .control16(control16_1),
        .control8 (control8_1)
    );

endmodule
