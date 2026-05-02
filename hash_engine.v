// =============================================================================
// hash_engine.v  -  Fixed with dummy read for first pixel
// =============================================================================
module hash_engine
(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        image_sel,
    output reg         bram_en,
    output reg  [14:0] bram_addr,
    input  wire [11:0] bram_dout,
    output reg  [31:0] hash_out,
    output reg         hash_done
);

    parameter TOTAL_PIXELS = 16384;
    localparam BASE_A = 15'd0;
    localparam BASE_B = 15'd16384;

    localparam S_IDLE    = 3'd0;
    localparam S_PREREAD = 3'd1;   // dummy read
    localparam S_READ    = 3'd2;   // wait for data
    localparam S_HASH    = 3'd3;   // compute hash
    localparam S_DONE    = 3'd4;

    reg [2:0] state;
    reg [13:0] pixel_cnt;
    reg [14:0] base_addr;
    reg [31:0] hash_reg;

    function [31:0] rotl1;
        input [31:0] x;
        rotl1 = {x[30:0], x[31]};
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            bram_en    <= 0;
            bram_addr  <= 0;
            hash_out   <= 0;
            hash_done  <= 0;
            pixel_cnt  <= 0;
            hash_reg   <= 32'hDEADBEEF;
        end else begin
            hash_done <= 0;
            case (state)
                S_IDLE: begin
                    bram_en <= 0;
                    if (start) begin
                        base_addr <= image_sel ? BASE_B : BASE_A;
                        hash_reg  <= 32'hDEADBEEF;
                        pixel_cnt <= 0;
                        state     <= S_PREREAD;
                    end
                end

                // Dummy read to load bram_dout for first pixel
                S_PREREAD: begin
                    bram_en   <= 1'b1;
                    bram_addr <= base_addr + {1'b0, pixel_cnt}; // pixel_cnt = 0
                    state     <= S_READ;
                end

                S_READ: begin
                    // Wait one cycle for bram_dout to update
                    state <= S_HASH;
                end

                S_HASH: begin
                    // bram_dout is now valid from the previous read
                    hash_reg  <= rotl1(hash_reg) + (hash_reg ^ {20'b0, bram_dout});
                    pixel_cnt <= pixel_cnt + 1;

                    if (pixel_cnt == TOTAL_PIXELS - 1) begin
                        bram_en <= 0;
                        state   <= S_DONE;
                    end else begin
                        // Issue next read address
                        bram_addr <= base_addr + {1'b0, pixel_cnt + 1};
                        state     <= S_HASH;
                    end
                end

                S_DONE: begin
                    hash_out  <= hash_reg;
                    hash_done <= 1'b1;
                    state     <= S_IDLE;
                end
            endcase
        end
    end
endmodule