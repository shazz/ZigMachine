// The OSD test bitstream without its Xilinx primitives (rtl/board/osd_test_top.v
// adds the PLL, the PS7 and the serialiser), so CXXRTL can run it whole
// (tests/tb/osd_test_tb.cpp): the HDMI test pattern, the glass's OSD over it,
// and the glass's register block as the ARM's GP0 slave.
//
// One clock: the pixel clock also clocks the register block and the PS's GP0
// (MAXIGP0ACLK), so the block is clocked whenever the PL is configured, from
// the PL's own oscillator, whatever the FSBL did to FCLK0. The OSD's text RAM
// is written by osd_banner.v after reset, then by the ARM (REG OFF_OSD_TEXT).
// CTRL starts with CTRL_OSD set, so the banner is on screen at power-on.
//
// pat_* is the pattern before the overlay, for the testbench: the picture
// leaves three clocks behind it (zm_glass_osd.v).
`default_nettype none

module osd_test_core (
    input  wire        clk,
    input  wire        rst,
    // AXI3 slave (the PS's M_AXI_GP0), single beats: zm_glass_regs.v
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [15:0] s_awaddr,
    input  wire [11:0] s_awid,
    input  wire        s_wvalid,
    output wire        s_wready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output wire        s_bvalid,
    input  wire        s_bready,
    output wire [11:0] s_bid,
    output wire [1:0]  s_bresp,
    input  wire        s_arvalid,
    output wire        s_arready,
    input  wire [15:0] s_araddr,
    input  wire [11:0] s_arid,
    output wire        s_rvalid,
    input  wire        s_rready,
    output wire [31:0] s_rdata,
    output wire [11:0] s_rid,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    // the picture, to the DVI encoder
    output wire [7:0]  r, g, b,
    output wire        de, hsync, vsync,
    // the pattern under the OSD, and the banner writer's state (testbench)
    output wire [7:0]  pat_r, pat_g, pat_b,
    output wire        pat_de, pat_hs, pat_vs,
    output wire        banner_busy
);
`include "glass_map.vh"

    hdmi_pattern u_pat (.clk(clk), .rst(rst), .r(pat_r), .g(pat_g), .b(pat_b), .de(pat_de), .hsync(pat_hs),
                        .vsync(pat_vs));

    wire        osd_en, regs_we, banner_we;
    wire [23:0] osd_fg, osd_bg;
    wire [8:0]  regs_waddr, regs_wdata, banner_waddr, banner_wdata;
    zm_glass_regs #(.CTRL_INIT(ZG_CTRL_OSD)) u_regs (
        .clk(clk), .rst(rst),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr), .s_awid(s_awid),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bid(s_bid), .s_bresp(s_bresp),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr), .s_arid(s_arid),
        .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata), .s_rid(s_rid), .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .cpu_run(), .osd_en(osd_en), .osd_fg(osd_fg), .osd_bg(osd_bg), .load_base(), .load_size(), .joy(),
        .osd_we(regs_we), .osd_waddr(regs_waddr), .osd_wdata(regs_wdata),
        .key_valid(), .key_data(), .key_pop(1'b0), .cart_state_we(1'b0), .cart_state_in(32'd0),
        .cart_beat_we(1'b0), .cart_beat_in(32'd0), .ptr(), .ptr_ack(1'b0), .ptr_ack_seq(8'd0)
    );

    osd_banner u_banner (.clk(clk), .rst(rst), .we(banner_we), .waddr(banner_waddr), .wdata(banner_wdata),
                         .busy(banner_busy));

    // The banner owns the port for the 512 clocks after reset; the ARM cannot
    // have written yet (the PL was configuring, or its PLL relocking).
    zm_glass_osd u_osd (
        .clk(clk), .rst(rst), .en(osd_en), .fg(osd_fg), .bg(osd_bg), .wclk(clk),
        .we(banner_we || regs_we), .waddr(banner_we ? banner_waddr : regs_waddr),
        .wdata(banner_we ? banner_wdata : regs_wdata),
        .r(pat_r), .g(pat_g), .b(pat_b), .de(pat_de), .hsync(pat_hs), .vsync(pat_vs),
        .r_o(r), .g_o(g), .b_o(b), .de_o(de), .hs_o(hsync), .vs_o(vsync)
    );
endmodule

`default_nettype wire
