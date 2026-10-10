// The halftone pattern's bit for pixel (x, y): row y mod 16, bit x mod 16. The low
// four bits of a two's-complement coordinate are its (always positive) @mod(., 16).
`default_nettype none

module zm_blit_htbit (
    input  wire [255:0] ht,
    input  wire [3:0]   x,
    input  wire [3:0]   y,
    output wire         bit_o
);
    assign bit_o = ht[{y, x}];
endmodule
