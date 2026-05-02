// =============================================================================
// image_bram.v  -  Fixed with initialization and robust read/write
// =============================================================================
module image_bram
(
    input  wire        clk_a,
    input  wire        we_a,
    input  wire [14:0] addr_a,
    input  wire [11:0] din_a,
    output wire [11:0] dout_a,

    input  wire        clk_b,
    input  wire        en_b,
    input  wire [14:0] addr_b,
    output reg  [11:0] dout_b
);

    (* ram_style = "block" *)
    reg [11:0] mem [0:32767];

    // Initialize memory to 0 (avoids 'x' in simulation)
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < 32768; init_idx = init_idx + 1)
            mem[init_idx] = 12'h000;
    end

    // Port A - write with latched address (same as before)
    reg [11:0] dout_a_reg;
    reg [14:0] addr_a_reg;
    always @(posedge clk_a) begin
        addr_a_reg <= addr_a;
        if (we_a) begin
            mem[addr_a_reg] <= din_a;
            $display("BRAM WRITE: addr=%0d data=%h", addr_a_reg, din_a);
        end
        dout_a_reg <= mem[addr_a_reg];
    end
    assign dout_a = dout_a_reg;

    // Port B - read with register
    always @(posedge clk_b) begin
        if (en_b) begin
            dout_b <= mem[addr_b];
            $display("BRAM READ: addr=%0d data=%h", addr_b, mem[addr_b]);
        end
    end

endmodule