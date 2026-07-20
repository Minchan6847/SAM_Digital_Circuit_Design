module tb_Hamming_decoder;
    logic [16:1] input_message;
    wire [21:1] encoded_message;
    logic [21:1] corrupted_message;
    wire [16:1] decoded_message;
    wire [4:0] syndrome;

    integer total_tests;
    integer failures;
    integer current_error_position;

    Hamming_encoder enc_mod (
        .A(input_message),
        .B(encoded_message)
    );

    Hamming_decoder dec_mod (
        .A(corrupted_message),
        .B(decoded_message),
        .syndrome(syndrome)
    );

    task automatic check_message(input logic [16:1] message);
        integer error_position;
        begin
            //---- Test without an error. ----//
            total_tests = total_tests + 1;

            // Encode the message
            input_message = message;
            #1;

            // Decode the message
            corrupted_message = encoded_message;
            current_error_position = 0;
            #1;

            if (syndrome !== 5'd0) begin
                failures = failures + 1;
                $error("No-error syndrome mismatch: message=%b syndrome=%0d", input_message,
                       syndrome);
            end

            if (decoded_message !== input_message) begin
                failures = failures + 1;
                $error("No-error decode mismatch: input=%b decoded=%b", input_message,
                       decoded_message);
            end

            //---- Insert one error at every codeword position from 1 through 21. ----//
            for (
                error_position = 1; error_position <= 21; error_position = error_position + 1
            ) begin
                total_tests = total_tests + 1;

                // Decode the corrupted_message
                corrupted_message = encoded_message;
                corrupted_message[error_position] = ~corrupted_message[error_position];
                current_error_position = error_position;
                #1;

                if (syndrome !== error_position[4:0]) begin
                    failures = failures + 1;
                    $error("Syndrome mismatch: message=%b error_position=%0d syndrome=%0d",
                           input_message, error_position, syndrome);
                end

                if (decoded_message !== input_message) begin
                    failures = failures + 1;
                    $error("Decode mismatch: message=%b error_position=%0d decoded=%b",
                           input_message, error_position, decoded_message);
                end
            end

            #3;
        end
    endtask

    initial begin
        total_tests = 0;
        failures = 0;
        current_error_position = 0;
        input_message = '0;
        corrupted_message = '0;

        $dumpfile("tb_Hamming_decoder.vcd");
        $dumpvars(0, tb_Hamming_decoder);

        check_message(16'b0000000000000000);
        check_message(16'b1111111111111111);
        check_message(16'b1100101000111011);
        check_message(16'b1010101010101010);
        check_message(16'b0101010101010101);

        if (failures == 0) begin
            $display("PASS: %0d Hamming-code cases completed successfully.", total_tests);
        end else begin
            $display("FAIL: %0d of %0d checks failed.", failures, total_tests);
        end

        $finish;
    end
endmodule
