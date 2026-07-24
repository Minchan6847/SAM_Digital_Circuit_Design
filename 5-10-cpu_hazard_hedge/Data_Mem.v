module Data_Mem #(
    parameter DATA_SIZE = 32,
    parameter MEM_SIZE  = 1000
) (
    input  wire                 clk,
    input  wire                 MemWrite,
    input  wire                 MemRead,
    input  wire [DATA_SIZE-1:0] addr,
    input  wire [DATA_SIZE-1:0] W_data,
    output wire [DATA_SIZE-1:0] R_data
);

    // -------------------------------------------------------------------------
    // Word Alignment Offset Calculation
    // (예: 32비트 데이터 = 4바이트 = 2비트 Shift ($clog2(32/8) = 2))
    // -------------------------------------------------------------------------
    localparam BYTES_PER_WORD = DATA_SIZE / 8;
    localparam OFFSET_BITS = $clog2(BYTES_PER_WORD);

    // Memory Array Line Definition
    reg [DATA_SIZE-1:0] memory[0:MEM_SIZE-1];

    // -------------------------------------------------------------------------
    // Memory Write Logic (Synchronous)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (MemWrite) begin
            memory[addr>>OFFSET_BITS] <= W_data;
        end
    end

    // -------------------------------------------------------------------------
    // Memory Read Logic (Combinational)
    // -------------------------------------------------------------------------
    assign R_data = MemRead ? memory[addr>>OFFSET_BITS] : {DATA_SIZE{1'b0}};

endmodule
