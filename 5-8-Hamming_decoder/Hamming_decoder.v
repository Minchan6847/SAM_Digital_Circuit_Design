module Hamming_encoder (
    input  wire [16:1] A,
    output wire [21:1] B
);

    // Place 16 message bits into the non-parity positions.
    assign B[3]  = A[1];
    assign B[5]  = A[2];
    assign B[6]  = A[3];
    assign B[7]  = A[4];
    assign B[9]  = A[5];
    assign B[10] = A[6];
    assign B[11] = A[7];
    assign B[12] = A[8];
    assign B[13] = A[9];
    assign B[14] = A[10];
    assign B[15] = A[11];
    assign B[17] = A[12];
    assign B[18] = A[13];
    assign B[19] = A[14];
    assign B[20] = A[15];
    assign B[21] = A[16];

    // Generate even-parity bits at positions 1, 2, 4, 8, and 16.
    assign B[1]  = B[3] ^ B[5] ^ B[7] ^ B[9] ^ B[11] ^ B[13] ^ B[15] ^ B[17] ^ B[19] ^ B[21];
    assign B[2]  = B[3] ^ B[6] ^ B[7] ^ B[10] ^ B[11] ^ B[14] ^ B[15] ^ B[18] ^ B[19];
    assign B[4]  = B[5] ^ B[6] ^ B[7] ^ B[12] ^ B[13] ^ B[14] ^ B[15] ^ B[20] ^ B[21];
    assign B[8]  = B[9] ^ B[10] ^ B[11] ^ B[12] ^ B[13] ^ B[14] ^ B[15];
    assign B[16] = B[17] ^ B[18] ^ B[19] ^ B[20] ^ B[21];

endmodule

module Hamming_decoder (
    input  wire [21:1] A,
    output wire [16:1] B,
    output wire [ 4:0] syndrome
);
    wire check_p1;
    wire check_p2;
    wire check_p4;
    wire check_p8;
    wire check_p16;

    // error_pos[0] means no error.
    // error_pos[N] means an error at codeword position N.
    wire [21:0] error_pos;

    // Recalculate parity including each received parity bit.
    assign check_p1 = A[1]  ^ A[3]  ^ A[5]  ^ A[7]  ^ A[9]  ^
                      A[11] ^ A[13] ^ A[15] ^ A[17] ^ A[19] ^ A[21];

    assign check_p2 = A[2] ^ A[3] ^ A[6] ^ A[7] ^ A[10] ^ A[11] ^ A[14] ^ A[15] ^ A[18] ^ A[19];

    assign check_p4 = A[4] ^ A[5] ^ A[6] ^ A[7] ^ A[12] ^ A[13] ^ A[14] ^ A[15] ^ A[20] ^ A[21];

    assign check_p8 = A[8] ^ A[9] ^ A[10] ^ A[11] ^ A[12] ^ A[13] ^ A[14] ^ A[15];

    assign check_p16 = A[16] ^ A[17] ^ A[18] ^ A[19] ^ A[20] ^ A[21];

    // Numeric error position: {16, 8, 4, 2, 1} parity-check weights.
    assign syndrome = {check_p16, check_p8, check_p4, check_p2, check_p1};

    // Convert the numeric syndrome into a one-hot correction vector.
    // syndrome == 0:  error_pos[0]  = 1
    // syndrome == N:  error_pos[N]  = 1
    assign error_pos = 22'b1 << syndrome;

    // Extract and correct only the 16 data positions.
    assign B[1] = A[3] ^ error_pos[3];
    assign B[2] = A[5] ^ error_pos[5];
    assign B[3] = A[6] ^ error_pos[6];
    assign B[4] = A[7] ^ error_pos[7];
    assign B[5] = A[9] ^ error_pos[9];
    assign B[6] = A[10] ^ error_pos[10];
    assign B[7] = A[11] ^ error_pos[11];
    assign B[8] = A[12] ^ error_pos[12];
    assign B[9] = A[13] ^ error_pos[13];
    assign B[10] = A[14] ^ error_pos[14];
    assign B[11] = A[15] ^ error_pos[15];
    assign B[12] = A[17] ^ error_pos[17];
    assign B[13] = A[18] ^ error_pos[18];
    assign B[14] = A[19] ^ error_pos[19];
    assign B[15] = A[20] ^ error_pos[20];
    assign B[16] = A[21] ^ error_pos[21];

endmodule
