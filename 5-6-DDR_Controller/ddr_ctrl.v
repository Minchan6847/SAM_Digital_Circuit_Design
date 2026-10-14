module ddr_ctrl (
    input clk,
    input rstn,
    input i_req,
    output o_ack,
    input i_write,
    input [7:0] i_addr,
    input [63:0] i_wdata,
    output o_rd_en,
    output [63:0] o_rdata,
    output ck_t,
    output ck_c,
    output reg cke,
    output reg csn,
    output reg actn,
    output reg [1:0] bg,
    output reg [1:0] ba,
    output reg [17:0] a,  //rasn 16, casn 15, wen 14, bcn 12, ap 10
    inout [7:0] dq,
    inout dqs_t,
    inout dqs_c
);

    parameter INIT = 0, MRS = 1, IDLE = 2, ACT = 3, WR = 4, RD = 5, PRE = 6;
    parameter tRCD = 9, tCWL = 11, tCL = 10, tRP = 8;

    reg [4:0] cnt;
    reg [2:0] curr_state;
    reg rasn, casn, wen;
    reg [7:0] curr_addr;
    wire [3:0] curr_row, next_row;
    reg [63:0] curr_data;
    reg [7:0] dq_o;
    wire dq_oe;
    reg [63:0] read_data;
    reg data_read;
    wire [7:0] dq_i, next_addr;

    assign dq   = dq_oe ? dq_o : 'bZ;
    assign dq_i = dq;

    always @(posedge clk, negedge rstn)
        if (!rstn) curr_state <= 0;
        else begin
            case (curr_state)
                INIT: curr_state <= MRS;

                MRS: if (cnt == 1) curr_state <= IDLE;

                IDLE: if (i_req & o_ack) curr_state <= ACT;

                ACT: if (cnt == tRCD) curr_state <= i_write ? WR : RD;

                WR: begin
                    if (cnt == tCWL + 4 + 1) begin
                        if (curr_row == next_row) begin
                            curr_state <= i_write ? WR : RD;
                        end else begin
                            curr_state <= PRE;
                        end
                    end
                end

                RD: begin
                    if (cnt == tCL + 4 + 1) begin
                        if (curr_row == next_row) begin
                            curr_state <= i_write ? WR : RD;
                        end else begin
                            curr_state <= PRE;
                        end
                    end
                end

                PRE: if (cnt === tRP) curr_state <= IDLE;

            endcase
        end

    always @(posedge clk, negedge rstn)
        if (!rstn) begin
            cnt <= 0;
        end else begin
            case (curr_state)
                MRS: begin
                    if (cnt == 1) begin
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                ACT: begin
                    if (cnt == tRCD) begin
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                WR: begin
                    if (cnt == tCWL + 4 + 1) begin
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                RD: begin
                    if (cnt == tCL + 4 + 1) begin
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                PRE: begin
                    if (cnt == tRP) begin
                        cnt <= 0;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
            endcase
        end

    assign	o_ack = (curr_state == IDLE) ||
    (curr_state == WR && cnt == tCWL+4+1 && curr_row == next_row) ||
    (curr_state == RD && cnt == tCL +4+1 && curr_row == next_row) ;

    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            curr_addr <= 0;
            curr_data <= 0;
        end else if (i_req & o_ack) begin
            curr_addr <= i_addr;
            curr_data <= i_wdata;
        end
    end

    assign next_addr = i_addr;

    assign curr_row = curr_addr[7:4];
    assign next_row = next_addr[7:4];

    assign ck_t = clk;
    assign ck_c = ~clk;

    assign dqs_t = curr_state == WR && (cnt >= tCWL - 1 && cnt <= tCWL + 4) ? ck_t : 'bZ;
    assign dqs_c = curr_state == WR && (cnt >= tCWL - 1 && cnt <= tCWL + 4) ? ck_c : 'bZ;

    assign dq_oe = curr_state == WR && (cnt >= tCWL && cnt <= tCWL + 3);
    always @* begin
        dq_o = 8'h01;
        if (curr_state == WR) begin
            if (cnt == tCWL + 0) begin
                dq_o = dqs_t ? curr_data[7:0] : (dqs_c ? curr_data[15:8] : 'bZ);
            end else if (cnt == tCWL + 1) begin
                dq_o = dqs_t ? curr_data[23:16] : (dqs_c ? curr_data[31:24] : 'bZ);
            end else if (cnt == tCWL + 2) begin
                dq_o = dqs_t ? curr_data[39:32] : (dqs_c ? curr_data[47:40] : 'bZ);
            end else if (cnt == tCWL + 3) begin
                dq_o = dqs_t ? curr_data[55:48] : (dqs_c ? curr_data[63:56] : 'bZ);
            end
        end
    end

    always @(posedge dqs_c) begin
        if (cnt == tCL) read_data[7:0] <= dq_i;
        else if (cnt == tCL + 1) read_data[23:16] <= dq_i;
        else if (cnt == tCL + 2) read_data[39:32] <= dq_i;
        else if (cnt == tCL + 3) read_data[55:48] <= dq_i;
    end

    always @(posedge dqs_t) begin
        if (cnt == tCL) read_data[15:8] <= dq_i;
        else if (cnt == tCL + 1) read_data[31:24] <= dq_i;
        else if (cnt == tCL + 2) read_data[47:40] <= dq_i;
        else if (cnt == tCL + 3) read_data[63:56] <= dq_i;
    end

    assign o_rdata = read_data;
    assign o_rd_en = data_read;
    always @(posedge ck_t) begin
        if (curr_state == RD && cnt == tCL + 4) begin
            data_read <= 1;
        end else begin
            data_read <= 0;
        end
    end

    always @* begin
        {cke, csn, actn, rasn, casn, wen} = 6'b111111;  //NOP, DES

        if (cnt == 0) begin
            case (curr_state)
                MRS: begin
                    csn  = 0;
                    rasn = 0;
                    casn = 0;
                    wen  = 0;
                end
                ACT: begin
                    csn  = 0;
                    actn = 0;
                end
                WR: begin
                    csn  = 0;
                    casn = 0;
                    wen  = 0;
                end
                RD: begin
                    csn  = 0;
                    casn = 0;
                end
                PRE: begin
                    csn  = 0;
                    rasn = 0;
                    wen = 0;
                end
            endcase
        end else if (cnt == 1) begin
            case (curr_state)
                MRS: begin
                    csn  = 0;
                    rasn = 0;
                    casn = 0;
                    wen  = 0;
                end
            endcase
        end
    end

    always @* begin
        bg    = 0;
        ba    = 0;
        a     = 0;
        a[16] = rasn;
        a[15] = casn;
        a[14] = wen;

        case (curr_state)
            MRS: begin
                if (cnt == 0) begin  //MRS0
                    ba[1:0]        = 0;
                    {a[6:4], a[2]} = 'b0001;  //10
                    a[1:0]         = 'b00;
                end else if (cnt == 1) begin  //MRS2
                    ba[1:0] = 2;
                    a[5:3]  = 'b010;  //11
                end
            end
            ACT: begin
                a[3:0] = curr_addr[7:4];
            end
            WR, RD: begin
                a[3:0] = curr_addr[3:0];
            end
        endcase
    end
endmodule


/// dram ///
module dram (
    input ck_t,
    input ck_c,
    input cke,
    input csn,
    input actn,
    input [1:0] bg,
    input [1:0] ba,
    input [17:0] a,  //rasn 16, casn 15, wen 14, bcn 12, ap 10

    inout [7:0] dq,
    inout dqs_t,
    inout dqs_c
);
    parameter [4:0] ACT = 5'b00111, WR = 5'b01100, RD = 5'b01101, MRS = 5'b01000;  //opcode
    parameter tRCD = 9, tRP = 8;

    reg [3:0] tCWL, tCL;
    wire rasn = a[16];
    wire casn = a[15];
    wire wen = a[14];

    wire [4:0] opcode = {csn, actn, rasn, casn, wen};

    reg [3:0] row, col;
    reg write_op, read_op;
    reg [4:0] cnt;
    reg [63:0] curr_data;
    reg data_write;

    reg [7:0] dq_o;
    wire dq_oe;
    wire [7:0] dq_i;

    assign dq   = dq_oe ? dq_o : 'bZ;
    assign dq_i = dq;

    reg [63:0] mem[15:0][15:0];

    always @(posedge ck_t) begin
        case (opcode)
            ACT: begin
                row <= a[3:0];
            end
            WR, RD: begin
                col <= a[3:0];
            end
        endcase
    end

    always @(posedge ck_t) begin
        if (opcode == ACT) begin
            write_op <= 0;
        end else if (opcode == WR) begin
            write_op <= 1;
        end else if (cnt == tCWL + 4) begin
            write_op <= 0;
        end

        if (opcode == ACT) begin
            read_op <= 0;
        end else if (opcode == RD) begin
            read_op <= 1;
        end else if (cnt == tCL + 4) begin
            read_op <= 0;
        end
    end

    always @(posedge ck_t) begin
        if (opcode == ACT) begin
            cnt <= 0;
        end else if (opcode == WR || opcode == RD) begin
            cnt <= 1;
        end else if (write_op) begin
            cnt <= cnt == tCWL + 4 ? 0 : cnt + 1;
        end else if (read_op) begin
            cnt <= cnt == tCL + 4 ? 0 : cnt + 1;
        end
    end

    always @(posedge dqs_c) begin
        if (cnt == tCWL) curr_data[7:0] <= dq_i;
        else if (cnt == tCWL + 1) curr_data[23:16] <= dq_i;
        else if (cnt == tCWL + 2) curr_data[39:32] <= dq_i;
        else if (cnt == tCWL + 3) curr_data[55:48] <= dq_i;
    end

    always @(posedge dqs_t) begin
        if (cnt == tCWL) curr_data[15:8] <= dq_i;
        else if (cnt == tCWL + 1) curr_data[31:24] <= dq_i;
        else if (cnt == tCWL + 2) curr_data[47:40] <= dq_i;
        else if (cnt == tCWL + 3) curr_data[63:56] <= dq_i;
    end

    always @(posedge ck_t) begin
        if (write_op && cnt == tCWL + 4) begin
            data_write <= 1;
        end else begin
            data_write <= 0;
        end
    end

    always @(posedge ck_t) begin
        if (data_write) begin
            mem[row][col] <= curr_data;
        end
    end

    assign dqs_t = read_op && (cnt >= tCL - 1 && cnt <= tCL + 4) ? ck_t : 'bZ;
    assign dqs_c = read_op && (cnt >= tCL - 1 && cnt <= tCL + 4) ? ck_c : 'bZ;
    assign dq_oe = read_op && (cnt >= tCL && cnt <= tCL + 3);

    wire [63:0] read_data = mem[row][col];
    always @* begin
        dq_o = 8'h01;
        if (read_op) begin
            if (cnt == tCL + 0) begin
                dq_o = dqs_t ? read_data[7:0] : (dqs_c ? read_data[15:8] : 'bZ);
            end else if (cnt == tCL + 1) begin
                dq_o = dqs_t ? read_data[23:16] : (dqs_c ? read_data[31:24] : 'bZ);
            end else if (cnt == tCL + 2) begin
                dq_o = dqs_t ? read_data[39:32] : (dqs_c ? read_data[47:40] : 'bZ);
            end else if (cnt == tCL + 3) begin
                dq_o = dqs_t ? read_data[55:48] : (dqs_c ? read_data[63:56] : 'bZ);
            end
        end
    end

    always @(posedge ck_t) begin
        if (opcode == MRS) begin
            if ({bg[0], ba} == 0) begin
                tCL = ({a[6:4], a[2]} == 'b0001) ? 10 : 9;
            end else if ({bg[0], ba} == 2) begin
                tCWL = (a[5:3] == 'b010) ? 11 : 10;
            end
        end
    end

endmodule
