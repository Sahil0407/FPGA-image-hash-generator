// =============================================================================
// uart_tx.v  —  UART Transmitter
// Basys 3: 100 MHz clock, 115200 baud, 8-N-1
// =============================================================================
module uart_tx
#(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,    // byte to send
    input  wire       start,   // pulse high for 1 cycle to begin transmission
    output reg        tx,      // serial output
    output reg        busy     // high while transmitting
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            tx       <= 1'b1;
            busy     <= 1'b0;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            shift_reg<= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        shift_reg <= data;
                        state     <= S_START;
                        clk_cnt   <= 0;
                        busy      <= 1'b1;
                    end
                end

                S_START: begin
                    tx <= 1'b0;  // start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[bit_idx];  // LSB first
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;  // stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state   <= S_IDLE;
                        clk_cnt <= 0;
                        busy    <= 1'b0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end

endmodule
