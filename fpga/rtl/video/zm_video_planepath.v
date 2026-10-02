// The plane path: per-plane frame latches -> line geometry -> line fetch ->
// painter. Split out of zm_video_comp only to keep each file readable; the
// pieces are documented in their own modules.
`default_nettype none

module zm_video_planepath (
    input  wire          clk,
    input  wire          rst,
    input  wire          latch,
    input  wire          start,
    input  wire [1:0]    plane,
    input  wire [8:0]    py,
    input  wire [1023:0] regs,
    output wire          done,
    output wire          mem_req_valid,
    input  wire          mem_req_ready,
    output wire [31:0]   mem_req_addr,
    input  wire          mem_rsp_valid,
    input  wire [31:0]   mem_rsp_data,
    output wire          fb_we,
    output wire [7:0]    fb_waddr,
    output wire [31:0]   fb_wdata,
    output wire [7:0]    fb_raddr,
    input  wire [31:0]   fb_rdata,
    output wire [7:0]    pal_raddr,
    input  wire [31:0]   pal_rdata,
    output wire          lb_we_lo, lb_we_hi,
    output wire [8:0]    lb_addr,
    output wire [31:0]   lb_data,
    output wire          overflow
);
`include "zm_video_memmap.vh"

    wire [7:0] mode, seed;
    wire [31:0] base;
    wire [15:0] stride, hpos, hs, seen, upd_seen;
    wire top_open, bot_open, upd, upd_top, upd_bot;
    assign upd_seen = regs[ZM_REG_RES_FLICKER * 8 +: 16];
    zm_video_latch u_latch (
        .clk(clk), .latch(latch), .plane(plane), .regs(regs), .upd(upd), .upd_seen(upd_seen),
        .upd_top(upd_top), .upd_bot(upd_bot), .mode(mode), .base(base), .stride(stride), .hpos(hpos),
        .hs(hs), .seen(seen), .seed(seed), .top_open(top_open), .bot_open(bot_open));

    wire fetch_start, fetch_done, paint_start, paint_done;
    wire [31:0] fetch_addr;
    wire [10:0] fetch_len;
    wire [9:0] ncols, dst0;
    wire single, wrap, ov, band, band_open, hit, flick;
    wire [15:0] s0;
    wire [7:0] nbase;
    zm_video_plane u_plane (
        .clk(clk), .rst(rst), .start(start), .py(py), .mode(mode), .base(base), .stride(stride),
        .hpos(hpos), .hs(hs), .seen(seen), .seed(seed), .top_open(top_open), .bot_open(bot_open),
        .res(regs[ZM_REG_RESOLUTION * 8 +: 8]), .hs_live(regs[(ZM_REG_HSCROLL + plane * 2) * 8 +: 16]),
        .flicker(regs[ZM_REG_RES_FLICKER * 8 +: 16]), .upd(upd), .upd_top(upd_top), .upd_bot(upd_bot),
        .fetch_start(fetch_start), .fetch_addr(fetch_addr), .fetch_len(fetch_len), .fetch_done(fetch_done),
        .paint_start(paint_start), .ncols(ncols), .dst0(dst0), .single(single), .wrap(wrap), .ov(ov),
        .band(band), .band_open(band_open), .hit(hit), .flick(flick), .s0(s0), .nbase(nbase),
        .paint_done(paint_done), .done(done));

    zm_video_fetch u_fetch (
        .clk(clk), .rst(rst), .start(fetch_start), .addr(fetch_addr), .nbytes(fetch_len),
        .done(fetch_done), .overflow(overflow), .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready), .mem_req_addr(mem_req_addr), .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_data(mem_rsp_data), .buf_we(fb_we), .buf_waddr(fb_waddr), .buf_wdata(fb_wdata));

    zm_video_paint u_paint (
        .clk(clk), .rst(rst), .start(paint_start), .ncols(ncols), .align(fetch_addr[1:0]),
        .single(single), .dst0(dst0), .wrap(wrap), .stride(stride), .s0(s0), .ov(ov), .band(band),
        .band_open(band_open), .hit(hit), .flick(flick), .nbase(nbase), .fb_raddr(fb_raddr),
        .fb_rdata(fb_rdata), .pal_raddr(pal_raddr), .pal_rdata(pal_rdata), .lb_we_lo(lb_we_lo),
        .lb_we_hi(lb_we_hi), .lb_addr(lb_addr), .lb_data(lb_data), .done(paint_done));
endmodule

`default_nettype wire
