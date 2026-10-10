// base + y * stride: the address of row y of a channel, modulo 2^23 (every address an op may touch is below 0x700000). y is signed (a
// LINE walks through rows above the clip, whose address is never used). A multiplier
// the size of one DSP48: 18 x 18 signed.
`default_nettype none

module zm_blit_row (
    input  wire [22:0]        base,
    input  wire [15:0]        stride,
    input  wire signed [17:0] y,
    output wire [22:0]        addr
);
    wire signed [17:0] ss = {2'b00, stride};
    wire signed [35:0] prod = y * ss;
    assign addr = base + prod[22:0];
endmodule
