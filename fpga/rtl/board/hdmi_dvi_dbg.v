// zm_dvi_out (rtl/video/zm_dvi_out.v) with bring-up knobs, for the HDMI test
// bitstreams only (rtl/board/hdmi_test_top.v). With every knob at 0 it is
// zm_dvi_out with SERIALISER="OSERDES" (the cascade that gives no signal on the
// board); ODDR=1 is zm_dvi_out's default serialiser, the one that works.
//   REVERSE  send each 10-bit symbol MSB first (all four channels)
//   INVERT   invert the three data channels (the same as swapping their P and N)
//   ODDR     no OSERDES cascade: zm_dvi_out.v's zm_oddr10, a fabric shifter at 5x
//            the pixel clock feeding an ODDR, two bits a fast clock
//   SE       each pair as two single-ended outputs (P = bit, N = its inverse), for an
//            LVCMOS33 build that bypasses the TMDS_33 driver altogether (needs ODDR)
`default_nettype none

module hdmi_dvi_dbg #(
    parameter integer REVERSE = 0,
    parameter integer INVERT = 0,
    parameter integer ODDR = 0,
    parameter integer SE = 0
) (
    input  wire       pix_clk,
    input  wire       pix5x_clk,
    input  wire       rst,             // pix_clk's domain
    input  wire [7:0] r, g, b,
    input  wire       de, hsync, vsync,
    output wire [3:0] tmds_p,          // {clock, red, green, blue}
    output wire [3:0] tmds_n
);
    wire [39:0] sym;
    zm_tmds_enc u_b (.clk(pix_clk), .rst(rst), .de(de), .d(b), .c({vsync, hsync}), .q(sym[9:0]));
    zm_tmds_enc u_g (.clk(pix_clk), .rst(rst), .de(de), .d(g), .c(2'b00), .q(sym[19:10]));
    zm_tmds_enc u_r (.clk(pix_clk), .rst(rst), .de(de), .d(r), .c(2'b00), .q(sym[29:20]));
    assign sym[39:30] = 10'b0000011111;

    genvar i, k;
    generate
        for (i = 0; i < 4; i = i + 1) begin : ch
            wire [9:0] s0 = (INVERT != 0 && i < 3) ? ~sym[i*10 +: 10] : sym[i*10 +: 10];
            wire [9:0] s;
            for (k = 0; k < 10; k = k + 1) begin : bitsel
                assign s[k] = (REVERSE != 0) ? s0[9 - k] : s0[k];
            end
            wire serial, serial_n;
            if (ODDR != 0) begin : g_oddr
                zm_oddr10 u_ser (.clk(pix5x_clk), .d(s), .q(serial));
                // SE: the N pad needs its own ODDR (an IOB output takes no fabric inverter).
                if (SE != 0) begin : g_n
                    zm_oddr10 u_ser_n (.clk(pix5x_clk), .d(~s), .q(serial_n));
                end
            end else begin : g_oserdes
                zm_oserdes10 u_ser (.clk(pix5x_clk), .clkdiv(pix_clk), .rst(rst), .d(s), .q(serial));
            end
            if (SE != 0) begin : g_se
                OBUF u_p (.I(serial), .O(tmds_p[i]));
                OBUF u_n (.I(serial_n), .O(tmds_n[i]));
            end else begin : g_diff
                OBUFDS u_buf (.I(serial), .O(tmds_p[i]), .OB(tmds_n[i]));
            end
        end
    endgenerate
endmodule

`default_nettype wire
