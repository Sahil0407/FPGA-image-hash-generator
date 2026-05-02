// =============================================================================
// tb_top.v  —  Simulation testbench
// Simulates UART transmission of two small images and verifies hash comparison.
// Run in Vivado Simulator or ModelSim.
// =============================================================================
`timescale 1ns / 1ps

module tb_top;

    // ─────────────────────────────────────────────────────────────────────
    // Clock & reset
    // ─────────────────────────────────────────────────────────────────────
    reg clk     = 0;
    reg rst_btn = 1;

    always #5 clk = ~clk;   // 100 MHz

    // ─────────────────────────────────────────────────────────────────────
    // DUT
    // ─────────────────────────────────────────────────────────────────────
    reg        rx  = 1'b1;
    wire [15:0] led;

    top_controller #(.TOTAL_PIXELS(16)) dut (
        .clk     (clk),
        .rst_btn (rst_btn),
        .rx      (rx),
        .led     (led)
    );

    // ─────────────────────────────────────────────────────────────────────
    // UART byte sender task (115200 baud = 8680ns per bit)
    // ─────────────────────────────────────────────────────────────────────
    localparam BIT_PERIOD = 8680;   // ns

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // Start bit
            rx = 1'b0;
            #BIT_PERIOD;
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #BIT_PERIOD;
            end
            // Stop bit
            rx = 1'b1;
            #BIT_PERIOD;
        end
    endtask

    task uart_send_pixel;
        input [11:0] pixel;
        begin
            uart_send_byte({4'b0000, pixel[11:8]});  // high byte
            uart_send_byte(pixel[7:0]);               // low byte
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────
    // Test: send 4 pixels (just to verify protocol, not full 128x128)
    // For full sim, increase pixel count — too slow at bit-level
    // ─────────────────────────────────────────────────────────────────────
    integer p;
    reg [11:0] test_pixel;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        // Hold reset
        #200;
        rst_btn = 0;
        #200;

        $display("=== Sending Image A command ===");
        uart_send_byte(8'hA0);   // CMD_LOAD_A

        // Send 16 test pixels (normally 16384 for 128x128)
        // Using red pixels (R=F, G=0, B=0) → 12'hF00
        for (p = 0; p < 16; p = p + 1) begin
            uart_send_pixel(12'hF00);
        end
        $display("Sent 16 Image A pixels");

        #5000;

        $display("=== Sending Image B command ===");
        uart_send_byte(8'hB0);   // CMD_LOAD_B

        // Send same 16 red pixels → hashes should match
        for (p = 0; p < 16; p = p + 1) begin
            uart_send_pixel(12'hF00);
        end
        $display("Sent 16 Image B pixels (identical to A)");

             #5000;
$display("pa_load_done = %b", dut.pa_load_done);

        $display("=== Sending COMPARE command ===");
        uart_send_byte(8'hC0);

        #50000;
   

        $display("LED = %b", led);
        $display("LED15 (MATCH)    = %b", led[15]);
        $display("LED14 (MISMATCH) = %b", led[14]);

        if (led[15])
            $display("PASS: Images match as expected");
        else
            $display("FAIL or images did not fully load (expected match)");
        $display("hash_a = %0h", dut.hash_a);
        $display("hash_b = %0h", dut.hash_b);
        $finish;
    end

endmodule
