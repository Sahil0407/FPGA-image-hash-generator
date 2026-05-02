// =============================================================================
// top_controller.v  —  FIXED: edge detection for load_done + auto-compare race
// =============================================================================
module top_controller
#(parameter TOTAL_PIXELS = 16384)
(
    input  wire        clk,
    input  wire        rst_btn,
    input  wire        rx,
    output wire [15:0] led
);

    wire rst = rst_btn;

    // Submodule wires
    wire [7:0]  uart_data;
    wire        uart_valid;
    wire        pa_bram_we;
    wire [13:0] pa_bram_addr;
    wire [11:0] pa_bram_wdata;
    wire        pa_load_done;
    wire        pa_image_sel;
    wire        pa_do_compare;
    wire [14:0] bram_write_addr;
    wire [11:0] bram_dout_b, bram_dout_a;
    reg         hash_start;
    reg         hash_img_sel;
    wire        hash_bram_en;
    wire [14:0] hash_bram_addr;
    wire [31:0] hash_out;
    wire        hash_done;
    reg  [31:0] hash_a, hash_b;
    reg         hash_a_valid, hash_b_valid;
    reg         loading, hashing, match, mismatch;
    reg         auto_compare_req;

    // -------------------------------------------------------------------------
    // Edge detection for pa_load_done (one-cycle pulse)
    // -------------------------------------------------------------------------
    reg load_done_ff;
    wire load_done_edge = pa_load_done && !load_done_ff;
    always @(posedge clk or posedge rst) begin
        if (rst) load_done_ff <= 0;
        else load_done_ff <= pa_load_done;
    end

    // -------------------------------------------------------------------------
    // Instantiate submodules (unchanged)
    // -------------------------------------------------------------------------
    uart_rx #(.CLK_FREQ(100_000_000), .BAUD_RATE(115_200)) u_uart_rx (
        .clk(clk), .rst(rst), .rx(rx), .data(uart_data), .valid(uart_valid)
    );
    pixel_assembler #(.TOTAL_PIXELS(TOTAL_PIXELS)) u_pa (
        .clk(clk), .rst(rst), .rx_data(uart_data), .rx_valid(uart_valid),
        .bram_we(pa_bram_we), .bram_addr(pa_bram_addr), .bram_wdata(pa_bram_wdata),
        .load_done(pa_load_done), .image_sel(pa_image_sel), .do_compare(pa_do_compare)
    );
    assign bram_write_addr = {pa_image_sel, pa_bram_addr};
    image_bram u_bram (
        .clk_a(clk), .we_a(pa_bram_we), .addr_a(bram_write_addr), .din_a(pa_bram_wdata), .dout_a(bram_dout_a),
        .clk_b(clk), .en_b(hash_bram_en), .addr_b(hash_bram_addr), .dout_b(bram_dout_b)
    );
    hash_engine #(.TOTAL_PIXELS(TOTAL_PIXELS)) u_hash (
        .clk(clk), .rst(rst), .start(hash_start), .image_sel(hash_img_sel),
        .bram_en(hash_bram_en), .bram_addr(hash_bram_addr), .bram_dout(bram_dout_b),
        .hash_out(hash_out), .hash_done(hash_done)
    );

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    localparam C_IDLE       = 3'd0;
    localparam C_DELAY      = 3'd1;   // NEW: one-cycle delay
    localparam C_START_HASH = 3'd2;
    localparam C_WAIT_HASH  = 3'd3;
    localparam C_COMPARE    = 3'd4;

    reg [2:0] ctrl_state;
    reg [31:0] hash_a, hash_b;
    reg hash_a_valid, hash_b_valid;
    reg loading, hashing, match, mismatch;
    reg auto_compare_req;
    reg hash_start, hash_img_sel;
    wire both_valid = hash_a_valid && hash_b_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ctrl_state       <= C_IDLE;
            hash_start       <= 0;
            hash_img_sel     <= 0;
            hash_a           <= 0;
            hash_b           <= 0;
            hash_a_valid     <= 0;
            hash_b_valid     <= 0;
            loading          <= 0;
            hashing          <= 0;
            match            <= 0;
            mismatch         <= 0;
            auto_compare_req <= 0;
        end else begin
            hash_start <= 0;

            if (pa_do_compare)
                auto_compare_req <= 1'b1;

            case (ctrl_state)
                C_IDLE: begin
                    loading <= 0;
                    hashing <= 0;
                    if (load_done_edge) begin
                        loading      <= 1'b1;
                        hash_img_sel <= pa_image_sel;
                        ctrl_state   <= C_DELAY;   // ← go to delay
                    end else if (auto_compare_req && both_valid) begin
                        auto_compare_req <= 0;
                        ctrl_state       <= C_COMPARE;
                    end
                end

                C_DELAY: begin
                    loading    <= 1'b1;
                    ctrl_state <= C_START_HASH;
                end

                C_START_HASH: begin
                    loading    <= 0;
                    hashing    <= 1'b1;
                    hash_start <= 1'b1;
                    ctrl_state <= C_WAIT_HASH;
                end

                C_WAIT_HASH: begin
                    hashing <= 1'b1;
                    if (hash_done) begin
                        hashing <= 0;
                        if (hash_img_sel == 1'b0) begin
                            hash_a       <= hash_out;
                            hash_a_valid <= 1'b1;
                            $display("Image A hash computed: %h", hash_out);
                        end else begin
                            hash_b       <= hash_out;
                            hash_b_valid <= 1'b1;
                            $display("Image B hash computed: %h", hash_out);
                        end
                        if (both_valid)
                            ctrl_state <= C_COMPARE;
                        else
                            ctrl_state <= C_IDLE;
                    end
                end

                C_COMPARE: begin
                    if (hash_a == hash_b) begin
                        match    <= 1'b1;
                        mismatch <= 1'b0;
                    end else begin
                        match    <= 1'b0;
                        mismatch <= 1'b1;
                    end
                    ctrl_state <= C_IDLE;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // LED output (unchanged)
    // -------------------------------------------------------------------------
    assign led = {
        match,          // LED15
        mismatch,       // LED14
        loading,        // LED13
        hashing,        // LED12
        hash_b_valid,   // LED11
        hash_a_valid,   // LED10
        pa_image_sel,   // LED9
        1'b0,           // LED8
        hash_out[7:0]
    };

endmodule
