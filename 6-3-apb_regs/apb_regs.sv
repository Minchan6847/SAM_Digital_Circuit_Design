module apb_regs #(
    parameter int unsigned DW = 32,
    parameter int unsigned AW = 5
) (
    input logic pclk,
    input logic presetn,

    input  logic [AW-1:0] paddr,
    input  logic          psel,
    input  logic          penable,
    input  logic          pwrite,
    input  logic [DW-1:0] pwdata,
    output logic [DW-1:0] prdata,
    output logic          pready,
    output logic          pslverr,

    input  logic [31:0] status32,
    input  logic [15:0] status16,
    input  logic [ 7:0] status8,
    output logic [31:0] control32,
    output logic [15:0] control16,
    output logic [ 7:0] control8
);

    localparam logic [AW-1:0] ADDR_ID = 5'h00;
    localparam logic [AW-1:0] ADDR_CONTROL32 = 5'h04;
    localparam logic [AW-1:0] ADDR_CONTROL16 = 5'h08;
    localparam logic [AW-1:0] ADDR_CONTROL8 = 5'h0C;
    localparam logic [AW-1:0] ADDR_STATUS32 = 5'h14;
    localparam logic [AW-1:0] ADDR_STATUS16 = 5'h18;
    localparam logic [AW-1:0] ADDR_STATUS8 = 5'h1C;

    logic valid_read_addr;
    logic valid_write_addr;
    logic apb_write_fire;

    /*
     * This example is a zero-wait-state APB slave.
     * A transfer completes on a rising edge when:
     *   PSEL=1, PENABLE=1, PREADY=1
     */
    assign pready         = 1'b1;
    assign apb_write_fire = psel && penable && pwrite && pready;

    always_comb begin
        valid_read_addr = 1'b1;

        unique case (paddr)
            ADDR_ID,
            ADDR_CONTROL32,
            ADDR_CONTROL16,
            ADDR_CONTROL8,
            ADDR_STATUS32,
            ADDR_STATUS16,
            ADDR_STATUS8:
            ;
            default: valid_read_addr = 1'b0;
        endcase
    end

    always_comb begin
        valid_write_addr = 1'b1;

        unique case (paddr)
            ADDR_CONTROL32, ADDR_CONTROL16, ADDR_CONTROL8: ;
            default: valid_write_addr = 1'b0;
        endcase
    end

    /*
     * PSLVERR is meaningful only in the access phase. Because PREADY is
     * permanently high, every access phase is also the final transfer cycle.
     */
    always_comb begin
        pslverr = 1'b0;

        if (psel && penable) begin
            if (pwrite) pslverr = !valid_write_addr;
            else pslverr = !valid_read_addr;
        end
    end

    /*
     * Combinational read mux. PRDATA is sampled by the APB master at the end
     * of a completed read transfer. Outside a selected read, it is driven to 0.
     */
    always_comb begin
        prdata = '0;

        if (psel && !pwrite) begin
            unique case (paddr)
                ADDR_ID:        prdata = 32'h1234_5678;
                ADDR_CONTROL32: prdata = control32;
                ADDR_CONTROL16: prdata = control16;
                ADDR_CONTROL8:  prdata = control8;
                ADDR_STATUS32:  prdata = status32;
                ADDR_STATUS16:  prdata = status16;
                ADDR_STATUS8:   prdata = status8;
                default:        prdata = '0;
            endcase
        end
    end

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            control32 <= 32'h0000_0000;
            control16 <= 16'h0000;
            control8  <= 8'h00;
        end else if (apb_write_fire && valid_write_addr) begin
            unique case (paddr)
                ADDR_CONTROL32: control32 <= pwdata[31:0];
                ADDR_CONTROL16: control16 <= pwdata[15:0];
                ADDR_CONTROL8: control8 <= pwdata[7:0];
                default: ;
            endcase
        end
    end

    initial begin
        if (AW < 5) $fatal(1, "AW must be at least 5");
        if (DW != 32) $fatal(1, "This register map currently requires DW=32");
    end

endmodule
