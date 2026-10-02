// DVI out: the scanout's RGB and syncs as four TMDS pairs (DVI 1.0; HDMI sinks
// take it as plain DVI: no data islands, so no audio and no InfoFrames).
// Channel 0 carries blue and {VSYNC, HSYNC} in blanking, channels 1 and 2 green
// and red, and the clock channel sends the pixel clock as 5 ones then 5 zeros.
//
// Each 10-bit symbol is serialised by an OSERDESE2 master/slave pair in 10:1
// DDR mode: CLKDIV is the pixel clock, CLK five times it (200 MHz for
// 800x600@60), which is the 7-series' documented way to 10:1. The pairs leave
// through OBUFDS; the TMDS_33 standard is set by the board's XDC. This file
// instantiates Xilinx primitives, so it is synthesised for the board only; the
// encoders are tested on their own (tests/tb/zm_tmds_tb.cpp).
`default_nettype none

module zm_dvi_out (
    input  wire       pix_clk,
    input  wire       pix5x_clk,
    input  wire       rst,             // pix_clk's domain
    input  wire [7:0] r, g, b,
    input  wire       de, hsync, vsync,
    output wire [3:0] tmds_p,          // {clock, red, green, blue}
    output wire [3:0] tmds_n
);
    wire [39:0] sym;  // channel i's symbol at [i*10 +: 10]
    zm_tmds_enc u_b (.clk(pix_clk), .rst(rst), .de(de), .d(b), .c({vsync, hsync}), .q(sym[9:0]));
    zm_tmds_enc u_g (.clk(pix_clk), .rst(rst), .de(de), .d(g), .c(2'b00), .q(sym[19:10]));
    zm_tmds_enc u_r (.clk(pix_clk), .rst(rst), .de(de), .d(r), .c(2'b00), .q(sym[29:20]));
    assign sym[39:30] = 10'b0000011111;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ch
            wire serial;
            zm_oserdes10 u_ser (.clk(pix5x_clk), .clkdiv(pix_clk), .rst(rst), .d(sym[i*10 +: 10]), .q(serial));
            OBUFDS u_buf (.I(serial), .O(tmds_p[i]), .OB(tmds_n[i]));
        end
    endgenerate
endmodule

// 10:1 DDR serialiser: an OSERDESE2 master (bits 0..7) cascaded with a slave
// (bits 8 and 9 on its D3/D4), bit 0 first (UG471, "OSERDESE2 width expansion").
module zm_oserdes10 (
    input  wire       clk,
    input  wire       clkdiv,
    input  wire       rst,
    input  wire [9:0] d,
    output wire       q
);
    wire shift1, shift2;
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("MASTER"),
                .TRISTATE_WIDTH(1)) u_master (
        .OQ(q), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(), .SHIFTOUT2(), .TBYTEOUT(),
        .CLK(clk), .CLKDIV(clkdiv), .D1(d[0]), .D2(d[1]), .D3(d[2]), .D4(d[3]), .D5(d[4]), .D6(d[5]),
        .D7(d[6]), .D8(d[7]), .OCE(1'b1), .RST(rst), .SHIFTIN1(shift1), .SHIFTIN2(shift2),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("SLAVE"),
                .TRISTATE_WIDTH(1)) u_slave (
        .OQ(), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(shift1), .SHIFTOUT2(shift2), .TBYTEOUT(),
        .CLK(clk), .CLKDIV(clkdiv), .D1(1'b0), .D2(1'b0), .D3(d[8]), .D4(d[9]), .D5(1'b0), .D6(1'b0),
        .D7(1'b0), .D8(1'b0), .OCE(1'b1), .RST(rst), .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
endmodule

`default_nettype wire
