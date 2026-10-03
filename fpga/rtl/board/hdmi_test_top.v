// The second bitstream: HDMI1 out, nothing of the machine but its video timing
// and its DVI encoder. A test pattern (rtl/board/hdmi_pattern.v) at VESA
// 800x600@60 leaves through rtl/board/hdmi_dvi_dbg.v: by default exactly
// rtl/video/zm_dvi_out.v (TMDS encoders + 10:1 DDR OSERDESE2), with `define`d
// bring-up variants (Makefile hdmi-test-*). DVI only: HPD and DDC unconnected.
//
// Clocks: one PLLE2 off PL_CLK_50M (N18), VCO 50 x 20 = 1000 MHz (the -1 grade's
// PLL VCO range is 800-1600 MHz, PFD 19-450 MHz: DIVCLK 1 puts it at 50), /25 =
// 40 MHz pixel clock, /5 = 200 MHz for the serialisers, both through a BUFG. The
// same PLL settings the board SoC uses (soc/zm_z7.py, LiteX's S7PLL picks them).
// Reset: the pixel domain is held until the PLL locks (two-flop synchroniser).
// LEDs (active low): PL_LED1 toggles every 0.5 s counted on the PIXEL clock, so a
// 1 Hz blink proves the PLL's 40 MHz; PL_LED2 is lit while the PLL is locked.
`default_nettype none

module hdmi_test_top (
    input  wire PL_CLK_50M,
    output wire PL_LED1,
    output wire PL_LED2,
    output wire HDMI1_CLK_P,
    output wire HDMI1_CLK_N,
    output wire HDMI1_D0_P,
    output wire HDMI1_D0_N,
    output wire HDMI1_D1_P,
    output wire HDMI1_D1_N,
    output wire HDMI1_D2_P,
    output wire HDMI1_D2_N
);
    wire fb, pix_pll, pix5x_pll, locked, pix_clk, pix5x_clk;
    PLLE2_ADV #(
        .CLKIN1_PERIOD(20.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(20),
        .CLKOUT0_DIVIDE(25), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(5), .CLKOUT1_PHASE(0.0),
        .REF_JITTER1(0.01), .STARTUP_WAIT("FALSE")
    ) u_pll (
        .CLKIN1(PL_CLK_50M), .CLKFBIN(fb), .CLKFBOUT(fb), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0(pix_pll), .CLKOUT1(pix5x_pll), .LOCKED(locked)
    );
    BUFG u_bufg_pix (.I(pix_pll), .O(pix_clk));
    BUFG u_bufg_pix5x (.I(pix5x_pll), .O(pix5x_clk));

    // Held in reset until the PLL locks; released synchronously to pix_clk.
    reg [1:0] rst_sync = 2'b11;
    always @(posedge pix_clk or negedge locked) begin
        if (!locked) rst_sync <= 2'b11;
        else rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst = rst_sync[1];

    wire [7:0] r, g, b;
    wire       de, hsync, vsync;
    hdmi_pattern u_pat (.clk(pix_clk), .rst(rst), .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync));

    // Bring-up variants (Makefile hdmi-test-*), chosen by `define: the default is
    // rtl/video/zm_dvi_out.v's behaviour exactly.
`ifdef HDMI_REVERSE
    localparam integer REVERSE = 1;
`else
    localparam integer REVERSE = 0;
`endif
`ifdef HDMI_INVERT
    localparam integer INVERT = 1;
`else
    localparam integer INVERT = 0;
`endif
`ifdef HDMI_SE
    localparam integer SE = 1;
`else
    localparam integer SE = 0;
`endif
`ifdef HDMI_ODDR
    localparam integer USE_ODDR = 1;
`else
    localparam integer USE_ODDR = 0;
`endif
    wire [3:0] tmds_p, tmds_n;
`ifdef HDMI_CLKONLY
    // No serialiser at all: the 40 MHz pixel clock through an ODDR on the clock
    // pair, the data pairs driven to a constant.
    wire clk_out;
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC")) u_clk_oddr (
        .Q(clk_out), .C(pix_clk), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));
    OBUFDS u_clk_buf (.I(clk_out), .O(tmds_p[3]), .OB(tmds_n[3]));
    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : idle
            OBUFDS u_buf (.I(1'b0), .O(tmds_p[i]), .OB(tmds_n[i]));
        end
    endgenerate
`else
    hdmi_dvi_dbg #(.REVERSE(REVERSE), .INVERT(INVERT), .ODDR(USE_ODDR), .SE(SE)) u_dvi (
        .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .rst(rst),
        .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync),
        .tmds_p(tmds_p), .tmds_n(tmds_n)
    );
`endif
    assign {HDMI1_CLK_P, HDMI1_D2_P, HDMI1_D1_P, HDMI1_D0_P} = tmds_p;
    assign {HDMI1_CLK_N, HDMI1_D2_N, HDMI1_D1_N, HDMI1_D0_N} = tmds_n;

    localparam integer HALF_PERIOD = 20_000_000;  // 0.5 s at 40 MHz
    reg [24:0] count = 25'd0;
    reg        phase = 1'b0;
    always @(posedge pix_clk) begin
        if (count == HALF_PERIOD - 1) begin
            count <= 25'd0;
            phase <= ~phase;
        end else begin
            count <= count + 25'd1;
        end
    end

    assign PL_LED1 = ~phase;   // blinks at 1 Hz from the pixel clock
    assign PL_LED2 = ~locked;  // lit while the PLL is locked
endmodule

`default_nettype wire
