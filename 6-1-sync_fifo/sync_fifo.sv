module sync_fifo #(
    parameter int unsigned DEPTH    = 8,
    parameter int unsigned WIDTH    = 32,
    parameter int unsigned AF_LEVEL = 1,
    parameter int unsigned AE_LEVEL = 1
) (
    input  wire             clk,
    input  wire             rstn,
    input  wire             push,
    input  wire             pop,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty,
    output wire             a_full,
    output wire             a_empty
);

    localparam int unsigned PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    logic [WIDTH-1:0] mem[0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [COUNT_W-1:0] count;

    wire pop_fire = pop && !empty;
    // A push is also accepted when full if a valid pop occurs in the same cycle.
    wire push_fire = push && (!full || pop_fire);

    assign full    = (count == DEPTH);
    assign empty   = (count == 0);
    assign a_full  = (count >= (DEPTH - AF_LEVEL));
    assign a_empty = (count <= AE_LEVEL);

    // First-word fall-through output. Data is meaningful only when empty == 0.
    assign dout = empty ? '0 : mem[rd_ptr];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (push_fire) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == DEPTH - 1) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (pop_fire) begin
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            case ({
                push_fire, pop_fire
            })
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    initial begin
        if (DEPTH < 1) $fatal(1, "DEPTH must be at least 1");
        if (WIDTH < 1) $fatal(1, "WIDTH must be at least 1");
        if (AF_LEVEL > DEPTH) $fatal(1, "AF_LEVEL must be in the range 0..DEPTH");
        if (AE_LEVEL > DEPTH) $fatal(1, "AE_LEVEL must be in the range 0..DEPTH");
    end

endmodule
