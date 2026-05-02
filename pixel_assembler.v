// =============================================================================
// pixel_assembler.v
//
// Protocol (from PC Python script):
//   Each 12-bit pixel is sent as 2 bytes, big-endian:
//     Byte 0 (HIGH): [7:4] = 0000 padding,  [3:0] = pixel[11:8]
//     Byte 1 (LOW) : [7:0] = pixel[7:0]
//
//   Total bytes for 128x128 = 128*128*2 = 32768 bytes
//
//   Before sending pixels, PC sends a 1-byte command:
//     0xA0 = "load image A"
//     0xB0 = "load image B"
//     0xC0 = "compare hashes"
//
// Outputs:
//   bram_we      - write enable to BRAM
//   bram_addr    - 14-bit write address (0..16383 for 128*128)
//   bram_wdata   - 12-bit pixel data
//   load_done    - pulses 1 cycle when all pixels received
//   image_sel    - 0 = loading image A, 1 = loading image B
//   do_compare   - pulses 1 cycle on compare command
// =============================================================================
module pixel_assembler
(
    input  wire        clk,
    input  wire        rst,

    // from UART RX
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // to BRAM write port
    output reg         bram_we,
    output reg  [13:0] bram_addr,   // 14 bits = 16384 locations (128*128)
    output reg  [11:0] bram_wdata,

    // status
    output reg         load_done,   // image fully received
    output reg         image_sel,   // 0=A, 1=B
    output reg         do_compare   // compare command received
);

    parameter TOTAL_PIXELS = 128 * 128;  // 16384

    // Commands
    localparam CMD_LOAD_A   = 8'hA0;
    localparam CMD_LOAD_B   = 8'hB0;
    localparam CMD_COMPARE  = 8'hC0;

    // States
    localparam S_WAIT_CMD   = 2'd0;   // waiting for command byte
    localparam S_HIGH_BYTE  = 2'd1;   // waiting for high nibble byte
    localparam S_LOW_BYTE   = 2'd2;   // waiting for low byte

    reg [1:0]  state;
    reg [13:0] pixel_cnt;
    reg [3:0]  high_nibble;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_WAIT_CMD;
            pixel_cnt  <= 0;
            bram_we    <= 0;
            bram_addr  <= 0;
            bram_wdata <= 0;
            load_done  <= 0;
            image_sel  <= 0;
            do_compare <= 0;
            high_nibble<= 0;
        end else begin
            // Default pulse signals
            bram_we    <= 0;
            load_done  <= 0;
            do_compare <= 0;

            if (rx_valid) begin
                case (state)
                    // ---------------------------------------------------------
                    S_WAIT_CMD: begin
                        case (rx_data)
                            CMD_LOAD_A: begin
                                image_sel <= 1'b0;
                                pixel_cnt <= 0;
                                bram_addr <= 0;
                                state     <= S_HIGH_BYTE;
                            end
                            CMD_LOAD_B: begin
                                image_sel <= 1'b1;
                                pixel_cnt <= 0;
                                // Image B stored at offset 16384 in BRAM
                                // (BRAM is 32768 deep x 12-bit)
                                bram_addr <= 14'd0;
                                state     <= S_HIGH_BYTE;
                            end
                            CMD_COMPARE: begin
                                do_compare <= 1'b1;
                                state      <= S_WAIT_CMD;
                            end
                            default: state <= S_WAIT_CMD;
                        endcase
                    end

                    // ---------------------------------------------------------
                    // First byte: upper nibble of 12-bit pixel in [3:0]
                    S_HIGH_BYTE: begin
                        high_nibble <= rx_data[3:0];
                        state       <= S_LOW_BYTE;
                    end

                    // ---------------------------------------------------------
                    // Second byte: lower 8 bits of 12-bit pixel
                    // Inside S_LOW_BYTE, replace with:
                    S_LOW_BYTE: begin
                        bram_wdata <= {high_nibble, rx_data};
                        bram_we    <= 1'b1;
                        // Write to current bram_addr
                        $display("PA: Writing pixel %0d at addr %0d data=%h", pixel_cnt, bram_addr, {high_nibble, rx_data});
                        if (pixel_cnt == TOTAL_PIXELS - 1) begin
                            load_done <= 1'b1;
                            state     <= S_WAIT_CMD;
                            // Do not increment address for last pixel
                        end else begin
                            bram_addr <= bram_addr + 1;
                            state     <= S_HIGH_BYTE;
                        end
                        pixel_cnt <= pixel_cnt + 1;
                    end 
                endcase
            end
        end
    end

endmodule
