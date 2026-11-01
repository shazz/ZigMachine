// The halftone pattern's bit for pixel (x, y): bit x mod 16 of row y mod 16 (the row is read
// from zm_blit_regs' LUTRAM at y's low four bits). The low four bits of a two's-complement
// coordinate are its (always positive) @mod(., 16).
`default_nettype none

module zm_blit_htbit (
    input  wire [15:0] row,
    input  wire [3:0]  x,
    output wire        bit_o
);
    assign bit_o = row[x];
endmodule
