// Third bitstream: read the monitor's EDID over HDMI1's DDC and show it on
// HDMI1 as hex (rtl/board/edid_core.v), to be photographed and decoded on the
// host (tools/edid_decode.py). The video leaves as DVI through zm_dvi_out's ODDR
// serialiser, the one proven on the board (make hdmi-test-oddr).
//
// DDC pins: HDMI1_I2C_SCL (R19) and HDMI1_I2C_SDA (T19), LVCMOS33. On the board
// each goes through a 2N7002 bidirectional level shifter to the connector's 5 V
// side, with 4.7k pull-ups on both sides (Z7-LITE_R11, "HDMI TX": R98/R99 to
// 3V3, R101/R102 to the HDMI 5 V), so the FPGA only pulls low or lets go: an
// IOBUF with I tied to 0 and T = !pull. HDMI1_HPD (P19) is only shown; the
// schematic names its net HDMI1_HPDN (a 2N7002 between it and the connector).
// LEDs (active low): PL_LED1 lit while the last EDID read was good, PL_LED2 lit
// while the PLL is locked.
`default_nettype none

module edid_test_top (
    input  wire PL_CLK_50M,
    output wire PL_LED1,
    output wire PL_LED2,
    inout  wire HDMI1_I2C_SCL,
    inout  wire HDMI1_I2C_SDA,
    input  wire HDMI1_HPD,
    output wire HDMI1_CLK_P,
    output wire HDMI1_CLK_N,
    output wire HDMI1_D0_P,
    output wire HDMI1_D0_N,
    output wire HDMI1_D1_P,
    output wire HDMI1_D1_N,
    output wire HDMI1_D2_P,
    output wire HDMI1_D2_N
);
    wire pix_clk, pix5x_clk, locked, rst;
    hdmi_clk u_clk (.PL_CLK_50M(PL_CLK_50M), .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .locked(locked), .rst(rst));

    wire scl_low, sda_low, scl_in, sda_in;
    IOBUF u_scl (.IO(HDMI1_I2C_SCL), .I(1'b0), .T(!scl_low), .O(scl_in));
    IOBUF u_sda (.IO(HDMI1_I2C_SDA), .I(1'b0), .T(!sda_low), .O(sda_in));

    wire [7:0] r, g, b;
    wire       de, hsync, vsync;
    wire [2:0] status;
    edid_core u_core (
        .clk(pix_clk), .rst(rst), .scl_low(scl_low), .sda_low(sda_low), .scl_in(scl_in), .sda_in(sda_in),
        .hpd(HDMI1_HPD), .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync),
        .ch(), .status(status), .reads());

    wire [3:0] tmds_p, tmds_n;
    zm_dvi_out u_dvi (.pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .rst(rst), .r(r), .g(g), .b(b),
                      .de(de), .hsync(hsync), .vsync(vsync), .tmds_p(tmds_p), .tmds_n(tmds_n));
    assign {HDMI1_CLK_P, HDMI1_D2_P, HDMI1_D1_P, HDMI1_D0_P} = tmds_p;
    assign {HDMI1_CLK_N, HDMI1_D2_N, HDMI1_D1_N, HDMI1_D0_N} = tmds_n;

    assign PL_LED1 = !(status == 3'd1);
    assign PL_LED2 = !locked;
endmodule

`default_nettype wire
