// rtl/board/edid_core.v with a shorter retry period (2^22 clocks, 0.1 s) so the
// CXXRTL testbench (tests/tb/edid_core_tb.cpp) reaches a TIMEOUT in a few
// million clocks. Everything else is the board's: QUARTER 200 (50 kHz SCL).
`default_nettype none

module edid_core_top (
    input  wire       clk,
    input  wire       rst,
    output wire       scl_low,
    output wire       sda_low,
    input  wire       scl_in,
    input  wire       sda_in,
    input  wire       hpd,
    output wire [7:0] r, g, b,
    output wire       de, hsync, vsync,
    output wire [7:0] ch,
    output wire [2:0] status,
    output wire [7:0] reads
);
    edid_core #(.PERIOD_BITS(22)) u (
        .clk(clk), .rst(rst), .scl_low(scl_low), .sda_low(sda_low), .scl_in(scl_in), .sda_in(sda_in),
        .hpd(hpd), .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync), .ch(ch),
        .status(status), .reads(reads));
endmodule

`default_nettype wire
