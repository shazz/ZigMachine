// Test top for tests/tb/zm_tmds_ser_tb.cpp: one TMDS channel as zm_dvi_out
// wires it, the encoder in the pixel domain and the 10:1 shifter at 5x, with
// the ODDR left to the testbench (its D1, D2 are `q[0]`, `q[1]`).
`default_nettype none

module zm_tmds_ser (
    input  wire       pix_clk,
    input  wire       clk5,
    input  wire       rst,
    input  wire       de,
    input  wire [7:0] d,
    input  wire [1:0] c,
    output wire [9:0] sym,
    output wire [1:0] q
);
    zm_tmds_enc u_enc (.clk(pix_clk), .rst(rst), .de(de), .d(d), .c(c), .q(sym));
    zm_tmds_shift u_shift (.clk(clk5), .d(sym), .q(q));
endmodule

`default_nettype wire
