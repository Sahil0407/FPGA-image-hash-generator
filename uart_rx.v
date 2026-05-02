// =============================================================================
// uart_rx.v  —  UART Receiver
// Basys 3: 100 MHz clock, 115200 baud, 8-N-1
// =============================================================================
module uart_rx
#(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,            // serial input pin (connected to USB-UART bridge)
    output reg  [7:0] data,    // received byte
    output reg  valid          // pulses high for 1 cycle when data is ready
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868 cycles @ 100 MHz

    // -------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    // Two-FF synchroniser to avoid metastability
    reg rx_sync0, rx_sync1;
    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            shift_reg<= 0;
            data     <= 0;
            valid    <= 0;
        end else begin
            valid <= 0;  // default: not valid

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (rx_sync1 == 1'b0) begin   // falling edge = start bit
                        state   <= S_START;
                        clk_cnt <= 0;
                    end
                end

                // ---------------------------------------------------------
                // Wait half a bit period, then sample in the middle of start
                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_sync1 == 1'b0) begin  // still low → valid start
                            state   <= S_DATA;
                            clk_cnt <= 0;
                            bit_idx <= 0;
                        end else begin
                            state <= S_IDLE;          // glitch, ignore
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt           <= 0;
                        shift_reg[bit_idx] <= rx_sync1;  // LSB first
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ---------------------------------------------------------
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (rx_sync1 == 1'b1) begin   // valid stop bit
                            data  <= shift_reg;
                            valid <= 1'b1;
                        end
                        state   <= S_IDLE;
                        clk_cnt <= 0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end

endmodule
