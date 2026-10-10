// Fifth bitstream: the glass's OSD on HDMI1 over the test pattern, and its
// register block on the PS's M_AXI_GP0 at 0x43C0_0000, so U-Boot can drive it
// (fpga/tools/osd_uboot_demo.sh). Everything but the primitives is
// rtl/board/osd_test_core.v, simulated whole by tests/tb/osd_test_tb.cpp.
//
// At power-on the OSD shows a banner the PL wrote itself (osd_banner.v), so the
// overlay is proven even if GP0 is not. From U-Boot, `md.l 0x43C00000 1` reads
// the ID (0x5A4D474C) and the OSD registers change the screen.
//
// Clocks: hdmi_clk.v's PLL off PL_CLK_50M: 40 MHz pixel clock, 200 MHz for the
// ODDR serialisers (zm_dvi_out's default, the one proven on the board). The
// pixel clock is also MAXIGP0ACLK: the GP0 slave runs off the PL's oscillator,
// not FCLK0, and answers every single-beat access (zm_glass_regs.v), so a U-Boot
// md/mw cannot hang the ARM once this bitstream is loaded and the PS-PL level
// shifters are on (the demo script checks them first).
// LEDs (active low): PL_LED1 toggles on every GP0 response (each md.l / mw.l
// word flips it), PL_LED2 is lit while the PLL is locked.
`default_nettype none

module osd_test_top (
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
    wire pix_clk, pix5x_clk, locked, rst;
    hdmi_clk u_clk (.PL_CLK_50M(PL_CLK_50M), .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .locked(locked), .rst(rst));

    // M_AXI_GP0, the PS as master. Only the single-beat subset is used: the
    // burst, lock, cache, prot and qos outputs are left open (soc/zm_glass.py).
    wire        awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready, rlast;
    wire [31:0] awaddr, araddr, wdata, rdata;
    wire [11:0] awid, arid, bid, rid;
    wire [3:0]  wstrb;
    wire [1:0]  bresp, rresp;
    PS7 u_ps7 (
        .MAXIGP0ACLK(pix_clk),
        .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWID(awid),
        .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready), .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb),
        .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready), .MAXIGP0BID(bid), .MAXIGP0BRESP(bresp),
        .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready), .MAXIGP0ARADDR(araddr), .MAXIGP0ARID(arid),
        .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready), .MAXIGP0RDATA(rdata), .MAXIGP0RID(rid),
        .MAXIGP0RRESP(rresp), .MAXIGP0RLAST(rlast)
    );

    wire [7:0] r, g, b;
    wire       de, hsync, vsync;
    osd_test_core u_core (
        .clk(pix_clk), .rst(rst),
        .s_awvalid(awvalid), .s_awready(awready), .s_awaddr(awaddr[15:0]), .s_awid(awid),
        .s_wvalid(wvalid), .s_wready(wready), .s_wdata(wdata), .s_wstrb(wstrb),
        .s_bvalid(bvalid), .s_bready(bready), .s_bid(bid), .s_bresp(bresp),
        .s_arvalid(arvalid), .s_arready(arready), .s_araddr(araddr[15:0]), .s_arid(arid),
        .s_rvalid(rvalid), .s_rready(rready), .s_rdata(rdata), .s_rid(rid), .s_rresp(rresp), .s_rlast(rlast),
        .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync),
        .pat_r(), .pat_g(), .pat_b(), .pat_de(), .pat_hs(), .pat_vs(), .banner_busy()
    );

    wire [3:0] tmds_p, tmds_n;
    zm_dvi_out u_dvi (
        .pix_clk(pix_clk), .pix5x_clk(pix5x_clk), .rst(rst),
        .r(r), .g(g), .b(b), .de(de), .hsync(hsync), .vsync(vsync), .tmds_p(tmds_p), .tmds_n(tmds_n)
    );
    assign {HDMI1_CLK_P, HDMI1_D2_P, HDMI1_D1_P, HDMI1_D0_P} = tmds_p;
    assign {HDMI1_CLK_N, HDMI1_D2_N, HDMI1_D1_N, HDMI1_D0_N} = tmds_n;

    reg activity = 1'b0;
    always @(posedge pix_clk)
        if ((bvalid && bready) || (rvalid && rready)) activity <= ~activity;
    assign PL_LED1 = ~activity;
    assign PL_LED2 = ~locked;
endmodule

`default_nettype wire
