// Testbench top for ASTROLABE's mailbox (tests/tb/zm_astro_tb.cpp): the glass block as the
// ARM reaches it over GP0, and zm_astro_mbox's two ports wired as soc/zm_glass.py and
// soc/zm_astro.py wire them, with ZIGGY's Wishbone port brought out.
`default_nettype none

module zm_astro_top (
    input  wire        clk,
    input  wire        rst,
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
    input  wire        key_pop,
    input  wire        cart_state_we,
    input  wire        cart_beat_we,
    input  wire        ptr_ack,
    input  wire        wb_cyc,
    input  wire        wb_stb,
    input  wire        wb_we,
    input  wire [9:0]  wb_adr,
    input  wire [31:0] wb_dat_w,
    input  wire [3:0]  wb_sel,
    output wire        wb_ack,
    output wire [31:0] wb_dat_r
);
    wire        mb_we, mb_re;
    wire [9:0]  mb_waddr, mb_raddr;
    wire [31:0] mb_wdata, mb_rdata;
    wire [3:0]  mb_wstrb;

    zm_glass_regs regs (
        .clk(clk), .rst(rst),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr), .s_awid(s_awid),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bid(s_bid), .s_bresp(s_bresp),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr), .s_arid(s_arid),
        .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata), .s_rid(s_rid), .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .cpu_run(), .osd_en(), .osd_stats(), .osd_x0(), .osd_y0(), .osd_fg(), .osd_bg(), .load_base(), .load_size(),
        .joy(), .boot_warm(), .audio_vol(), .osd_we(), .osd_waddr(), .osd_wdata(),
        .key_valid(), .key_data(), .key_pop(key_pop), .cart_state_we(cart_state_we), .cart_state_in(32'd0),
        .cart_beat_we(cart_beat_we), .cart_beat_in(32'd0), .ptr(), .ptr_ack(ptr_ack), .ptr_ack_seq(8'd0),
        .mb_we(mb_we), .mb_re(mb_re), .mb_waddr(mb_waddr), .mb_raddr(mb_raddr), .mb_wdata(mb_wdata),
        .mb_wstrb(mb_wstrb), .mb_rdata(mb_rdata)
    );

    zm_astro_mbox mbox (
        .clk(clk), .rst(rst),
        .wb_cyc(wb_cyc), .wb_stb(wb_stb), .wb_we(wb_we), .wb_adr(wb_adr), .wb_dat_w(wb_dat_w), .wb_sel(wb_sel),
        .wb_ack(wb_ack), .wb_dat_r(wb_dat_r),
        .arm_we(mb_we), .arm_waddr(mb_waddr), .arm_wdata(mb_wdata), .arm_wstrb(mb_wstrb),
        .arm_re(mb_re), .arm_raddr(mb_raddr), .arm_rdata(mb_rdata)
    );
endmodule

`default_nettype wire
