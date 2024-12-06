module MessageToCache (
    input logic NormalMode,
    input logic [1:0] Message,           // Assuming 2 bits for Message (1-4 values).
    input logic [31:0] address,          // Assuming 32-bit address.
    output logic [127:0] log_message     // Output string representation.
);

    // Combinational logic for message handling
    always_comb begin
        if (NormalMode) begin
            case (Message)
                2'b01: log_message = {"L2 to L1 Message: GETLINE\tAddress: ", address};
                2'b10: log_message = {"L2 to L1 Message: SENDLINE\tAddress: ", address};
                2'b11: log_message = {"L2 to L1 Message: INVALIDATELINE\tAddress: ", address};
                2'b100: log_message = {"L2 to L1 Message: EVICTLINE\tAddress: ", address};
                default: log_message = "Invalid Message";
            endcase
        end else begin
            log_message = "NormalMode Disabled";
        end
    end

endmodule
