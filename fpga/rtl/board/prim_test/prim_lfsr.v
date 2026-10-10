// The primitive self-test's pattern source (rtl/board/prim_test_top.v): a 32-bit
// Galois LFSR (x^32 + x^22 + x^2 + x + 1), one step per word, spread to W <= 96
// bits so that every bit of a word sees both values. A test runs one copy to
// make the data it writes and a second, reloaded with the same seed, to make the
// data it expects back: the reference never goes through the primitive.
`default_nettype none

module prim_lfsr #(
    parameter integer W = 32
) (
    input  wire         clk,
    input  wire         load,   // takes the seed (0 becomes 1: an LFSR at 0 stays there)
    input  wire [31:0]  seed,
    input  wire         step,
    output wire [W-1:0] q
);
    reg [31:0] s = 32'd1;
    always @(posedge clk)
        if (load) s <= (seed == 32'd0) ? 32'd1 : seed;
        else if (step) s <= {s[30:0], 1'b0} ^ (s[31] ? 32'h0040_0007 : 32'd0);

    wire [95:0] wide = {s ^ {s[18:0], s[31:19]}, ~{s[7:0], s[31:8]}, s};
    assign q = wide[W-1:0];
endmodule

`default_nettype wire
