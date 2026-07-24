`timescale 1ns / 1ps

module tb_cpu_hazard_hedge;

    logic clk;
    logic rst_n;

    integer i;
    integer error_count;
    integer phase_id;
    integer stall_count;

    logic [31:0] forbidden_reg_mask;

    bit saw_mem_forward;
    bit saw_wb_forward;
    bit saw_taken_branch;
    bit saw_jump_flush;

    bit saw_beq_not_taken;
    bit saw_bne_taken;
    bit saw_bne_not_taken;

    bit saw_no_stall_addi_rt;
    bit saw_no_stall_andi_rt;
    bit saw_no_stall_lw_rt;
    bit saw_no_stall_invalid_rtype;
    bit saw_true_load_add_stall;
    bit saw_true_load_store_stall;
    bit saw_wb_to_id_branch;

    bit pending_reg_reset_cancelled;
    bit pending_store_reset_cancelled;

    cpu_hazard_hedge ut (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    // =========================================================================
    // Instruction encoders
    // =========================================================================
    function automatic logic [31:0] enc_r(input logic [4:0] rs, input logic [4:0] rt,
                                          input logic [4:0] rd, input logic [4:0] shamt,
                                          input logic [5:0] funct);
        enc_r = {6'h00, rs, rt, rd, shamt, funct};
    endfunction

    function automatic logic [31:0] enc_i(input logic [5:0] opcode, input logic [4:0] rs,
                                          input logic [4:0] rt, input logic [15:0] imm);
        enc_i = {opcode, rs, rt, imm};
    endfunction

    function automatic logic [31:0] enc_j(input logic [5:0] opcode, input logic [25:0] target);
        enc_j = {opcode, target};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0000;

    // Phase 2 branch instructions
    localparam logic [31:0] P2_BEQ_NOT_TAKEN = {6'h04, 5'd3, 5'd4, 16'd2};
    localparam logic [31:0] P2_BNE_TAKEN = {6'h05, 5'd3, 5'd4, 16'd2};
    localparam logic [31:0] P2_BNE_NOT_TAKEN = {6'h05, 5'd3, 5'd3, 16'd2};

    // Phase 3 instructions used for precise hazard observation
    localparam logic [31:0] P3_ADDI_SAME_RT = {6'h08, 5'd0, 5'd1, 16'd9};
    localparam logic [31:0] P3_ANDI_SAME_RT = {6'h0C, 5'd0, 5'd2, 16'd7};
    localparam logic [31:0] P3_LW_SAME_RT = {6'h23, 5'd0, 5'd3, 16'd44};
    localparam logic [31:0] P3_LOAD_USE_ADD = {6'h00, 5'd4, 5'd0, 5'd5, 5'd0, 6'h20};
    localparam logic [31:0] P3_LOAD_USE_STORE = {6'h2B, 5'd0, 5'd6, 16'd48};
    localparam logic [31:0] P3_WB_ID_BRANCH = {6'h04, 5'd9, 5'd0, 16'd2};
    localparam logic [31:0] P3_INVALID_RTYPE = {6'h00, 5'd13, 5'd0, 5'd14, 5'd0, 6'h00};

    // =========================================================================
    // Common helpers
    // =========================================================================
    task automatic fail(input string message);
        begin
            $error("%s", message);
            error_count = error_count + 1;
        end
    endtask

    task automatic check_reg(input integer index, input logic [31:0] expected);
        begin
            if (ut.rf.register[index] !== expected) begin
                $error("REG FAIL: r%0d expected=%0d (0x%08h), actual=%0d (0x%08h)", index,
                       expected, expected, ut.rf.register[index], ut.rf.register[index]);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic check_mem(input integer index, input logic [31:0] expected);
        begin
            if (ut.dm.memory[index] !== expected) begin
                $error("MEM FAIL: memory[%0d] expected=%0d (0x%08h), actual=%0d (0x%08h)", index,
                       expected, expected, ut.dm.memory[index], ut.dm.memory[index]);
                error_count = error_count + 1;
            end
        end
    endtask

    task automatic clear_imem;
        begin
            for (i = 0; i < 100; i = i + 1) ut.im.memory[i] = NOP;
        end
    endtask

    task automatic reset_phase_observers;
        begin
            stall_count                = 0;
            forbidden_reg_mask         = 32'd0;
            saw_mem_forward            = 1'b0;
            saw_wb_forward             = 1'b0;
            saw_taken_branch           = 1'b0;
            saw_jump_flush             = 1'b0;
            saw_beq_not_taken          = 1'b0;
            saw_bne_taken              = 1'b0;
            saw_bne_not_taken          = 1'b0;
            saw_no_stall_addi_rt       = 1'b0;
            saw_no_stall_andi_rt       = 1'b0;
            saw_no_stall_lw_rt         = 1'b0;
            saw_no_stall_invalid_rtype = 1'b0;
            saw_true_load_add_stall    = 1'b0;
            saw_true_load_store_stall  = 1'b0;
            saw_wb_to_id_branch        = 1'b0;
        end
    endtask

    task automatic check_reset_controls;
        begin
            #1;
            if (ut.pcOut_IF !== 32'd0) fail("RESET FAIL: PC is not zero");

            if (ut.inst_ID !== 32'd0) fail("RESET FAIL: IF/ID instruction is not zero");

            // Data fields are intentionally allowed to retain X/old values.
            // Only architectural side-effect controls are required to reset.
            if ((ut.MemRead_EX   !== 1'b0) ||
                (ut.MemWrite_EX  !== 1'b0) ||
                (ut.RegWrite_EX  !== 1'b0) ||
                (ut.MemRead_MEM  !== 1'b0) ||
                (ut.MemWrite_MEM !== 1'b0) ||
                (ut.RegWrite_MEM !== 1'b0) ||
                (ut.RegWrite_WB  !== 1'b0)) begin
                fail("RESET FAIL: a side-effect control is not zero");
            end
        end
    endtask

    task automatic assert_reset;
        begin
            rst_n = 1'b0;
            check_reset_controls();
        end
    endtask

    task automatic release_reset;
        begin
            // Deassert reset away from the active rising edge.
            @(negedge clk);
            #1 rst_n = 1'b1;
        end
    endtask

    task automatic run_cycles(input integer count);
        begin
            repeat (count) @(negedge clk);
            #1;
        end
    endtask

    function automatic bit destination_is_known(input logic [4:0] dst);
        destination_is_known = (^dst !== 1'bx);
    endfunction

    // =========================================================================
    // Continuous protocol and coverage monitors
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // Side-effect controls must never be X after reset release.
            if ($isunknown(
                    {
                        ut.MemRead_EX,
                        ut.MemWrite_EX,
                        ut.RegWrite_EX,
                        ut.MemRead_MEM,
                        ut.MemWrite_MEM,
                        ut.RegWrite_MEM,
                        ut.RegWrite_WB
                    }
                )) begin
                fail("X FAIL: side-effect control contains X after reset release");
            end

            if (ut.Hazard === 1'b1) stall_count = stall_count + 1;

            if ((ut.ForwardA === 2'b10) || (ut.ForwardB === 2'b10)) saw_mem_forward = 1'b1;

            if ((ut.ForwardA === 2'b01) || (ut.ForwardB === 2'b01)) saw_wb_forward = 1'b1;

            if (ut.isBranch === 1'b1) saw_taken_branch = 1'b1;

            if ((ut.Jump === 1'b1) && (ut.IF_Flush === 1'b1)) saw_jump_flush = 1'b1;

            // A flushed or skipped instruction must never reach WB.
            if ((ut.RegWrite_WB === 1'b1) && destination_is_known(
                    ut.Dst_WB
                ) && forbidden_reg_mask[ut.Dst_WB]) begin
                $error("CONTROL HAZARD FAIL: wrong-path instruction attempted WB to r%0d",
                       ut.Dst_WB);
                error_count = error_count + 1;
            end

            // -------------------------------------------------------------
            // Phase 2: branch direction coverage
            // -------------------------------------------------------------
            if (phase_id == 2) begin
                if ((ut.inst_ID === P2_BEQ_NOT_TAKEN) && (ut.Hazard === 1'b0)) begin
                    saw_beq_not_taken = 1'b1;
                    if (ut.isBranch !== 1'b0)
                        fail("BEQ FAIL: unequal operands incorrectly took branch");
                end

                if ((ut.inst_ID === P2_BNE_TAKEN) && (ut.Hazard === 1'b0)) begin
                    saw_bne_taken = 1'b1;
                    if (ut.isBranch !== 1'b1)
                        fail("BNE FAIL: unequal operands did not take branch");
                end

                if ((ut.inst_ID === P2_BNE_NOT_TAKEN) && (ut.Hazard === 1'b0)) begin
                    saw_bne_not_taken = 1'b1;
                    if (ut.isBranch !== 1'b0)
                        fail("BNE FAIL: equal operands incorrectly took branch");
                end
            end

            // -------------------------------------------------------------
            // Phase 3: exact load-use precision checks
            // -------------------------------------------------------------
            if (phase_id == 3) begin
                if ((ut.inst_ID === P3_ADDI_SAME_RT) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd1)) begin
                    saw_no_stall_addi_rt = 1'b1;
                    if (ut.Hazard !== 1'b0)
                        fail("FALSE STALL: lw -> addi stalled because addi rt is a destination");
                end

                if ((ut.inst_ID === P3_ANDI_SAME_RT) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd2)) begin
                    saw_no_stall_andi_rt = 1'b1;
                    if (ut.Hazard !== 1'b0)
                        fail("FALSE STALL: lw -> andi stalled because andi rt is a destination");
                end

                if ((ut.inst_ID === P3_LW_SAME_RT) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd3)) begin
                    saw_no_stall_lw_rt = 1'b1;
                    if (ut.Hazard !== 1'b0)
                        fail(
                            "FALSE STALL: lw -> lw stalled because following lw rt is a destination");
                end

                if ((ut.inst_ID === P3_INVALID_RTYPE) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd13)) begin
                    saw_no_stall_invalid_rtype = 1'b1;
                    if (ut.Hazard !== 1'b0)
                        fail(
                            "FALSE STALL: unsupported R-type was treated as a source-using instruction");
                end

                if ((ut.inst_ID === P3_LOAD_USE_ADD) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd4)) begin
                    saw_true_load_add_stall = 1'b1;
                    if (ut.Hazard !== 1'b1)
                        fail("MISSING STALL: lw -> add dependency was not stalled");
                end

                if ((ut.inst_ID === P3_LOAD_USE_STORE) &&
                    (ut.MemRead_EX === 1'b1) &&
                    (ut.Rt_EX === 5'd6)) begin
                    saw_true_load_store_stall = 1'b1;
                    if (ut.Hazard !== 1'b1)
                        fail("MISSING STALL: lw -> sw store-data dependency was not stalled");
                end

                if ((ut.inst_ID === P3_WB_ID_BRANCH) && (ut.Hazard === 1'b0)) begin
                    saw_wb_to_id_branch = 1'b1;
                    if (ut.isBranch !== 1'b1)
                        fail("WB->ID FAIL: branch did not see the current WB value");
                end
            end
        end
    end

    // Verify PC/IF-ID hold, bubble insertion, and flush behavior after NBA updates.
    always @(posedge clk) begin : pipeline_protocol_checks
        logic [31:0] pc_before;
        logic [31:0] inst_before;
        logic [31:0] pc4_before;
        logic        hazard_before;
        logic        flush_before;

        if (rst_n) begin
            pc_before     = ut.pcOut_IF;
            inst_before   = ut.inst_ID;
            pc4_before    = ut.pcAdd4_ID;
            hazard_before = ut.Hazard;
            flush_before  = ut.IF_Flush;

            #1;

            if (hazard_before) begin
                if (ut.pcOut_IF !== pc_before)
                    fail("STALL PROTOCOL FAIL: PC changed during Hazard");

                if ((ut.inst_ID !== inst_before) || (ut.pcAdd4_ID !== pc4_before))
                    fail("STALL PROTOCOL FAIL: IF/ID changed during Hazard");

                if ((ut.MemRead_EX  !== 1'b0) ||
                    (ut.MemWrite_EX !== 1'b0) ||
                    (ut.RegWrite_EX !== 1'b0))
                    fail("STALL PROTOCOL FAIL: ID/EX side-effect controls were not bubbled");
            end

            if (flush_before && !hazard_before) begin
                if (ut.inst_ID !== 32'd0)
                    fail("FLUSH PROTOCOL FAIL: IF/ID instruction was not cleared");
            end
        end
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        clk                           = 1'b0;
        rst_n                         = 1'b0;
        error_count                   = 0;
        phase_id                      = 0;
        pending_reg_reset_cancelled   = 1'b0;
        pending_store_reset_cancelled = 1'b0;
        reset_phase_observers();
        clear_imem();

        // =====================================================================
        // PHASE 1
        // Existing end-to-end hazard test
        // =====================================================================
        phase_id = 1;
        reset_phase_observers();
        clear_imem();

        forbidden_reg_mask[7] = 1'b1;
        forbidden_reg_mask[8] = 1'b1;
        forbidden_reg_mask[15] = 1'b1;
        forbidden_reg_mask[16] = 1'b1;
        forbidden_reg_mask[17] = 1'b1;
        forbidden_reg_mask[18] = 1'b1;
        forbidden_reg_mask[21] = 1'b1;
        forbidden_reg_mask[22] = 1'b1;

        ut.im.memory[0] = enc_i(6'h08, 5'd0, 5'd1, 16'd5);
        ut.im.memory[1] = enc_i(6'h08, 5'd0, 5'd2, 16'd7);
        ut.im.memory[2] = enc_r(5'd1, 5'd2, 5'd3, 5'd0, 6'h20);
        ut.im.memory[3] = enc_r(5'd3, 5'd1, 5'd4, 5'd0, 6'h22);
        ut.im.memory[4] = enc_i(6'h2B, 5'd0, 5'd4, 16'd0);
        ut.im.memory[5] = enc_i(6'h23, 5'd0, 5'd5, 16'd0);
        ut.im.memory[6] = enc_r(5'd5, 5'd1, 5'd6, 5'd0, 6'h20);
        ut.im.memory[7] = enc_i(6'h04, 5'd6, 5'd3, 16'd2);
        ut.im.memory[8] = enc_i(6'h08, 5'd0, 5'd7, 16'd111);
        ut.im.memory[9] = enc_i(6'h08, 5'd0, 5'd8, 16'd222);
        ut.im.memory[10] = enc_i(6'h08, 5'd0, 5'd9, 16'd9);
        ut.im.memory[11] = enc_i(6'h2B, 5'd0, 5'd6, 16'd4);
        ut.im.memory[12] = enc_i(6'h23, 5'd0, 5'd10, 16'd4);
        ut.im.memory[13] = enc_i(6'h04, 5'd10, 5'd6, 16'd2);
        ut.im.memory[14] = enc_i(6'h08, 5'd0, 5'd15, 16'd333);
        ut.im.memory[15] = enc_i(6'h08, 5'd0, 5'd16, 16'd444);
        ut.im.memory[16] = enc_i(6'h08, 5'd0, 5'd11, 16'd11);
        ut.im.memory[17] = enc_j(6'h02, 26'd20);
        ut.im.memory[18] = enc_i(6'h08, 5'd0, 5'd17, 16'd555);
        ut.im.memory[19] = enc_i(6'h08, 5'd0, 5'd18, 16'd666);
        ut.im.memory[20] = enc_i(6'h08, 5'd0, 5'd12, 16'd12);
        ut.im.memory[21] = enc_i(6'h08, 5'd0, 5'd20, 16'd19);
        ut.im.memory[22] = enc_i(6'h08, 5'd0, 5'd19, 16'd19);
        ut.im.memory[23] = enc_i(6'h04, 5'd19, 5'd20, 16'd2);
        ut.im.memory[24] = enc_i(6'h08, 5'd0, 5'd21, 16'd777);
        ut.im.memory[25] = enc_i(6'h08, 5'd0, 5'd22, 16'd888);
        ut.im.memory[26] = enc_i(6'h08, 5'd0, 5'd13, 16'd255);
        ut.im.memory[27] = enc_i(6'h0C, 5'd13, 5'd14, 16'h000F);
        ut.im.memory[28] = enc_i(6'h2B, 5'd0, 5'd14, 16'd8);
        ut.im.memory[29] = enc_j(6'h02, 26'd29);

        assert_reset();
        release_reset();
        run_cycles(75);

        check_reg(1, 32'd5);
        check_reg(2, 32'd7);
        check_reg(3, 32'd12);
        check_reg(4, 32'd7);
        check_reg(5, 32'd7);
        check_reg(6, 32'd12);
        check_reg(9, 32'd9);
        check_reg(10, 32'd12);
        check_reg(11, 32'd11);
        check_reg(12, 32'd12);
        check_reg(13, 32'd255);
        check_reg(14, 32'd15);
        check_reg(19, 32'd19);
        check_reg(20, 32'd19);

        check_mem(0, 32'd7);
        check_mem(1, 32'd12);
        check_mem(2, 32'd15);

        if (stall_count != 7) begin
            $error("PHASE 1 STALL FAIL: expected=7, actual=%0d", stall_count);
            error_count = error_count + 1;
        end

        if (!saw_mem_forward) fail("PHASE 1 COVERAGE FAIL: MEM->EX forwarding not observed");
        if (!saw_wb_forward) fail("PHASE 1 COVERAGE FAIL: WB->EX forwarding not observed");
        if (!saw_taken_branch) fail("PHASE 1 COVERAGE FAIL: taken branch not observed");
        if (!saw_jump_flush) fail("PHASE 1 COVERAGE FAIL: jump flush not observed");

        // =====================================================================
        // PHASE 2
        // ISA decode, branch directions, zero register, unsupported instructions
        // =====================================================================
        phase_id = 0;
        assert_reset();
        phase_id = 2;
        reset_phase_observers();
        clear_imem();

        forbidden_reg_mask[14] = 1'b1;
        forbidden_reg_mask[15] = 1'b1;
        forbidden_reg_mask[18] = 1'b1;

        // Wrong-path store target must remain unchanged.
        ut.dm.memory[3] = 32'hCAFE_BABE;

        ut.im.memory[0] = enc_i(6'h08, 5'd0, 5'd1, 16'hFFFF);
        // addi r1, r0, -1

        ut.im.memory[1] = enc_i(6'h0C, 5'd1, 5'd2, 16'h8001);
        // andi r2, r1, 0x8001 -> 0x00008001

        ut.im.memory[2] = enc_i(6'h08, 5'd0, 5'd3, 16'h00F0);
        ut.im.memory[3] = enc_i(6'h08, 5'd0, 5'd4, 16'h0F0F);
        ut.im.memory[4] = enc_r(5'd3, 5'd4, 5'd5, 5'd0, 6'h24);
        // and

        ut.im.memory[5] = enc_r(5'd3, 5'd4, 5'd6, 5'd0, 6'h25);
        // or

        ut.im.memory[6] = enc_r(5'd4, 5'd3, 5'd7, 5'd0, 6'h22);
        // sub

        ut.im.memory[7] = enc_i(6'h08, 5'd0, 5'd8, 16'hFFFF);
        ut.im.memory[8] = enc_r(5'd8, 5'd0, 5'd9, 5'd0, 6'h2A);
        // signed slt: -1 < 0

        ut.im.memory[9] = enc_r(5'd0, 5'd8, 5'd10, 5'd0, 6'h2A);
        // signed slt: 0 < -1 is false

        ut.im.memory[10] = enc_i(6'h08, 5'd0, 5'd11, 16'd123);
        ut.im.memory[11] = enc_r(5'd3, 5'd4, 5'd11, 5'd0, 6'h00);
        // Unsupported R-type must not overwrite r11

        ut.im.memory[12] = enc_i(6'h08, 5'd0, 5'd0, 16'd99);
        // Attempt to write $zero

        ut.im.memory[13] = enc_i(6'h08, 5'd0, 5'd12, 16'd1);
        // Must still read r0 as zero

        ut.im.memory[14] = P2_BEQ_NOT_TAKEN;
        ut.im.memory[15] = enc_i(6'h08, 5'd0, 5'd13, 16'd13);

        ut.im.memory[16] = P2_BNE_TAKEN;
        ut.im.memory[17] = enc_i(6'h08, 5'd0, 5'd14, 16'd14);
        ut.im.memory[18] = enc_i(6'h08, 5'd0, 5'd15, 16'd15);
        ut.im.memory[19] = enc_i(6'h08, 5'd0, 5'd16, 16'd16);

        ut.im.memory[20] = P2_BNE_NOT_TAKEN;
        ut.im.memory[21] = enc_i(6'h08, 5'd0, 5'd17, 16'd17);

        ut.im.memory[22] = enc_i(6'h04, 5'd3, 5'd3, 16'd2);
        // Taken beq

        ut.im.memory[23] = enc_i(6'h2B, 5'd0, 5'd6, 16'd12);
        // Wrong-path store: must be flushed

        ut.im.memory[24] = enc_i(6'h08, 5'd0, 5'd18, 16'd18);
        ut.im.memory[25] = enc_i(6'h08, 5'd0, 5'd19, 16'd19);

        ut.im.memory[26] = enc_i(6'h08, 5'd0, 5'd20, 16'd20);
        ut.im.memory[27] = {6'h3F, 5'd0, 5'd20, 16'hFFFF};
        // Unsupported opcode must not overwrite r20

        ut.im.memory[28] = enc_j(6'h02, 26'd28);

        release_reset();
        run_cycles(85);

        check_reg(1, 32'hFFFF_FFFF);
        check_reg(2, 32'h0000_8001);
        check_reg(3, 32'h0000_00F0);
        check_reg(4, 32'h0000_0F0F);
        check_reg(5, 32'h0000_0000);
        check_reg(6, 32'h0000_0FFF);
        check_reg(7, 32'h0000_0E1F);
        check_reg(8, 32'hFFFF_FFFF);
        check_reg(9, 32'd1);
        check_reg(10, 32'd0);
        check_reg(11, 32'd123);
        check_reg(12, 32'd1);
        check_reg(13, 32'd13);
        check_reg(16, 32'd16);
        check_reg(17, 32'd17);
        check_reg(19, 32'd19);
        check_reg(20, 32'd20);

        check_mem(3, 32'hCAFE_BABE);

        if (!saw_beq_not_taken) fail("PHASE 2 COVERAGE FAIL: beq not-taken case not observed");
        if (!saw_bne_taken) fail("PHASE 2 COVERAGE FAIL: bne taken case not observed");
        if (!saw_bne_not_taken) fail("PHASE 2 COVERAGE FAIL: bne not-taken case not observed");

        // =====================================================================
        // PHASE 3
        // Exact hazard precision, forwarding priority, WB->ID branch behavior
        // =====================================================================
        phase_id = 0;
        assert_reset();
        phase_id = 3;
        reset_phase_observers();
        clear_imem();

        forbidden_reg_mask[10] = 1'b1;
        forbidden_reg_mask[11] = 1'b1;

        ut.dm.memory[10]       = 32'd42;  // byte address 40
        ut.dm.memory[11]       = 32'd77;  // byte address 44
        ut.dm.memory[12]       = 32'hDEAD_BEEF;  // byte address 48

        ut.im.memory[0]        = enc_i(6'h23, 5'd0, 5'd1, 16'd40);
        ut.im.memory[1]        = P3_ADDI_SAME_RT;

        ut.im.memory[2]        = enc_i(6'h23, 5'd0, 5'd2, 16'd40);
        ut.im.memory[3]        = P3_ANDI_SAME_RT;

        ut.im.memory[4]        = enc_i(6'h23, 5'd0, 5'd3, 16'd40);
        ut.im.memory[5]        = P3_LW_SAME_RT;

        ut.im.memory[6]        = enc_i(6'h23, 5'd0, 5'd4, 16'd40);
        ut.im.memory[7]        = P3_LOAD_USE_ADD;

        ut.im.memory[8]        = enc_i(6'h23, 5'd0, 5'd6, 16'd40);
        ut.im.memory[9]        = P3_LOAD_USE_STORE;

        ut.im.memory[10]       = enc_i(6'h08, 5'd0, 5'd7, 16'd1);
        ut.im.memory[11]       = enc_i(6'h08, 5'd0, 5'd7, 16'd2);
        ut.im.memory[12]       = enc_r(5'd7, 5'd0, 5'd8, 5'd0, 6'h20);
        // MEM producer must win over older WB producer

        ut.im.memory[13]       = enc_i(6'h08, 5'd0, 5'd9, 16'd0);
        ut.im.memory[14]       = NOP;
        ut.im.memory[15]       = NOP;
        ut.im.memory[16]       = P3_WB_ID_BRANCH;
        // Producer is in WB while branch is in ID

        ut.im.memory[17]       = enc_i(6'h08, 5'd0, 5'd10, 16'd10);
        ut.im.memory[18]       = enc_i(6'h08, 5'd0, 5'd11, 16'd11);
        ut.im.memory[19]       = enc_i(6'h08, 5'd0, 5'd12, 16'd12);

        ut.im.memory[20]       = enc_i(6'h23, 5'd0, 5'd13, 16'd40);
        ut.im.memory[21]       = P3_INVALID_RTYPE;
        // Unsupported R-type must behave as NOP and must not cause a stall.

        ut.im.memory[22]       = enc_j(6'h02, 26'd22);

        release_reset();
        run_cycles(90);

        check_reg(1, 32'd9);
        // P3_ANDI_SAME_RT is: andi r2, r0, 7
        // r0 & 7 = 0. This case tests that rt is treated as a destination
        // and therefore does not create a false load-use stall.
        check_reg(2, 32'd0);
        check_reg(3, 32'd77);
        check_reg(4, 32'd42);
        check_reg(5, 32'd42);
        check_reg(6, 32'd42);
        check_reg(7, 32'd2);
        check_reg(8, 32'd2);
        check_reg(9, 32'd0);
        check_reg(12, 32'd12);
        check_reg(13, 32'd42);
        check_mem(12, 32'd42);

        if (stall_count != 2) begin
            $error("PHASE 3 STALL FAIL: expected exactly 2 true load-use stalls, actual=%0d",
                   stall_count);
            error_count = error_count + 1;
        end

        if (!saw_no_stall_addi_rt)
            fail("PHASE 3 COVERAGE FAIL: lw->addi false-stall case not observed");
        if (!saw_no_stall_andi_rt)
            fail("PHASE 3 COVERAGE FAIL: lw->andi false-stall case not observed");
        if (!saw_no_stall_lw_rt)
            fail("PHASE 3 COVERAGE FAIL: lw->lw false-stall case not observed");
        if (!saw_no_stall_invalid_rtype)
            fail("PHASE 3 COVERAGE FAIL: unsupported R-type false-stall case not observed");
        if (!saw_true_load_add_stall)
            fail("PHASE 3 COVERAGE FAIL: true lw->add stall case not observed");
        if (!saw_true_load_store_stall)
            fail("PHASE 3 COVERAGE FAIL: true lw->sw stall case not observed");
        if (!saw_wb_to_id_branch) fail("PHASE 3 COVERAGE FAIL: WB->ID branch case not observed");

        // =====================================================================
        // PHASE 4A
        // Asynchronous reset must cancel an in-flight register write
        // =====================================================================
        phase_id = 0;
        assert_reset();
        phase_id = 4;
        reset_phase_observers();
        clear_imem();

        ut.im.memory[0] = enc_i(6'h08, 5'd0, 5'd20, 16'd55);
        ut.im.memory[1] = NOP;
        ut.im.memory[2] = NOP;
        ut.im.memory[3] = NOP;
        ut.im.memory[4] = enc_i(6'h08, 5'd0, 5'd20, 16'd99);
        ut.im.memory[5] = enc_j(6'h02, 26'd5);

        release_reset();

        wait (ut.rf.register[20] === 32'd55);
        wait ((ut.RegWrite_EX === 1'b1) && (ut.Dst_EX === 5'd20) && (ut.ALUResult_EX === 32'd99));

        #1 rst_n = 1'b0;
        check_reset_controls();
        repeat (2) @(posedge clk);
        #1;

        if (ut.rf.register[20] !== 32'd55)
            fail("ASYNC RESET FAIL: in-flight register write was not cancelled");
        else pending_reg_reset_cancelled = 1'b1;

        // =====================================================================
        // PHASE 4B
        // Asynchronous reset must cancel an in-flight memory write
        // =====================================================================
        phase_id = 0;
        clear_imem();
        ut.dm.memory[13] = 32'h1234_5678;  // byte address 52

        ut.im.memory[0] = enc_i(6'h08, 5'd0, 5'd21, 16'd33);
        ut.im.memory[1] = NOP;
        ut.im.memory[2] = NOP;
        ut.im.memory[3] = enc_i(6'h2B, 5'd0, 5'd21, 16'd52);
        ut.im.memory[4] = enc_j(6'h02, 26'd4);

        phase_id = 4;
        release_reset();

        wait ((ut.MemWrite_MEM === 1'b1) && (ut.ALUResult_MEM === 32'd52));

        #1 rst_n = 1'b0;
        check_reset_controls();
        repeat (2) @(posedge clk);
        #1;

        if (ut.dm.memory[13] !== 32'h1234_5678)
            fail("ASYNC RESET FAIL: in-flight memory write was not cancelled");
        else pending_store_reset_cancelled = 1'b1;

        // =====================================================================
        // Final report
        // =====================================================================
        if (!pending_reg_reset_cancelled)
            fail("COVERAGE FAIL: register-write reset cancellation not completed");
        if (!pending_store_reset_cancelled)
            fail("COVERAGE FAIL: memory-write reset cancellation not completed");

        if (error_count == 0) begin
            $display("================================================================");
            $display("PASS: comprehensive CPU RTL verification completed.");
            $display("Covered:");
            $display("  - reset and in-flight side-effect cancellation");
            $display("  - MEM/WB forwarding and forwarding priority");
            $display("  - true and false load-use hazard cases");
            $display("  - beq/bne taken and not-taken paths");
            $display("  - branch/jump flush and wrong-path side-effect blocking");
            $display("  - WB-to-ID register-file behavior");
            $display("  - add/sub/and/or/signed-slt/addi/andi/lw/sw");
            $display("  - zero register and unsupported instruction suppression");
            $display("================================================================");
        end else begin
            $fatal(1, "FAIL: %0d assertion/check error(s) detected", error_count);
        end

        $finish;
    end

    // Absolute simulation timeout
    initial begin
        #10000;
        $fatal(1, "TIMEOUT: comprehensive CPU test did not complete");
    end

endmodule
