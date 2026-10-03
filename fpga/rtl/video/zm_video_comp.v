// ZigMachine video compositor: builds the machine's 800x280 PFB and the
// browser's picture of it, a line and a pass at a time, in the machine's own
// order (plane-major: every line of the background, then every line of each
// enabled plane), from the register block, the 4 palettes, the BEAM table and
// the planes' framebuffers, exactly as machine/video.zig builds the PFB.
//
// Commands (`cmd_op`), each one pass over line `cmd_line` (zm_video_pass.v):
//   0 BG       paint the line from BACKGROUND / the BEAM table   (video.zig clear)
//   1 PLANE    composite plane `cmd_plane` over the PFB row      (renderPlane)
//   2 LATCH    latch plane `cmd_plane`'s frame registers         (top of renderPlane)
//   3 MIX      fold the PFB row alone into the picture           (no plane enabled)
//   4 PRESENT  the picture is complete: show it from the next VBL (zm_video_out.v)
// A PLANE pass taken with `cmd_mix` also folds the row into the picture, as the
// browser stacks canvas k over canvases 0..k-1 (zm_video_mix.v); `cmd_first`
// marks a line's first fold of the frame. The PFB rows go back to the region,
// where the machine keeps its PFB, so the frame is hashable as scene_hash does.
//
// Between passes is where the HBL handlers run: the sequencer (the cart CPU's
// firmware, fpga/cycles/vseq.c) calls the handler, waits until its stores have
// reached the CPU port (the snoop, soc/zm_video_snoop.py), then issues the pass.
// A pass reads every register and palette entry it needs after it is taken.
//
// Memory is reached through one read port (zm_video_fetch.v) and one write port
// (zm_video_rowio.v), both bursts of 64-bit beats at bus addresses.
`default_nettype none

module zm_video_comp (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] vbase,            // bus address of region offset 0 (HW_VIDEO_BASE)
    input  wire [31:0] dbase,            // bus address of the picture being built
    input  wire        d_ok,             // that picture may be written (zm_video_out.v)
    // CPU write port (the snoop): region-relative word address (byte offset / 4)
    input  wire        cpu_we,
    input  wire [20:0] cpu_waddr,
    input  wire [3:0]  cpu_be,
    input  wire [31:0] cpu_wdata,
    input  wire [2:0]  cpu_sel,          // {BEAM table, palettes, register block}, decoded by the writer
    input  wire [4:0]  cpu_rword,        // register read-back (offset / 4, < 0x20)
    output wire [31:0] cpu_rdata,
    // pass commands
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [2:0]  cmd_op,
    input  wire [1:0]  cmd_plane,
    input  wire [8:0]  cmd_line,
    input  wire        cmd_mix,          // fold this pass into the picture (zm_video_mix.v)
    input  wire        cmd_first,        // ... as the line's first layer of the frame
    output wire        painted,          // one clock: the pass has read all the CPU's state
    output wire        pass_done,        // one clock: the pass's rows are in memory
    output wire        present,          // one clock: a PRESENT command
    // memory: read bursts in, write bursts out
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        wr_req_valid,
    input  wire        wr_req_ready,
    output wire [31:0] wr_req_addr,
    output wire [9:0]  wr_req_len,
    output wire        wr_dat_valid,
    input  wire        wr_dat_ready,
    output wire [63:0] wr_dat,
    input  wire        wr_busy,
    output wire        overflow          // sticky: a line was too long to fetch
);
`include "zm_video_memmap.vh"

    localparam integer PAL_W = ZM_OFF_PAL / 4, BEAM_W = ZM_OFF_BEAM_TABLE / 4;
    // The writer decodes the region (soc/zm_video_snoop.py): no compare on this path.
    wire reg_sel = cpu_sel[0], pal_sel = cpu_sel[1], beam_sel = cpu_sel[2];
    wire [20:0] pal_idx = cpu_waddr - PAL_W, beam_idx = cpu_waddr - BEAM_W;

    // --- command taking: a pass that folds into the picture waits for `d_ok` ---
    wire busy;
    reg [1:0] plane;
    assign cmd_ready = !busy && (!cmd_mix || d_ok);
    wire take = cmd_valid && cmd_ready;
    wire latch = take && cmd_op == 3'd2;
    assign present = take && cmd_op == 3'd4;
    always @(posedge clk) if (take) plane <= cmd_plane;

    // --- registers ---
    wire [1023:0] regs;
    wire beam_upd, frame_inc;
    wire [31:0] beam_bg, beam_drops;
    zm_video_regs u_regs (
        .clk(clk), .cpu_we(cpu_we && reg_sel), .cpu_word(cpu_waddr[4:0]), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cpu_rword(cpu_rword), .cpu_rdata(cpu_rdata), .beam_upd(beam_upd),
        .beam_bg(beam_bg), .beam_drops(beam_drops), .frame_inc(frame_inc), .regs(regs));

    // --- memories: palettes, BEAM table, fetch buffer (64-bit beats), line buffer (two halves) ---
    wire [7:0] pal_raddr, fb_raddr, fb_waddr;
    wire [5:0] beam_raddr;
    wire [31:0] pal_rdata, beam_rdata;
    wire [63:0] fb_rdata, fb_wdata;
    wire fb_we;
    zm_video_sdpram #(.AW(10), .DW(32)) u_pal (.clk(clk), .we(cpu_we && pal_sel ? cpu_be : 4'd0),
        .waddr(pal_idx[9:0]), .wdata(cpu_wdata), .raddr({plane, pal_raddr}), .rdata(pal_rdata));
    zm_video_sdpram #(.AW(6), .DW(32)) u_beam (.clk(clk), .we(cpu_we && beam_sel ? cpu_be : 4'd0),
        .waddr(beam_idx[5:0]), .wdata(cpu_wdata), .raddr(beam_raddr), .rdata(beam_rdata));
    zm_video_sdpram #(.AW(8), .DW(64)) u_fbuf (.clk(clk), .we({8{fb_we}}), .waddr(fb_waddr),
        .wdata(fb_wdata), .raddr(fb_raddr), .rdata(fb_rdata));

    wire bg_we, pt_lo, pt_hi, ld_lb_we, ld_acc_we;
    wire [8:0] bg_addr, pt_addr, ld_addr, mix_raddr, st_raddr;
    wire [31:0] bg_data, pt_data;
    wire [63:0] ld_lb_data, lb_rdata;
    wire [47:0] ld_acc_data, acc_rdata;
    wire mix_busy;
    wire [8:0] lb_waddr = bg_we ? bg_addr : ld_lb_we ? ld_addr : pt_addr;
    wire [63:0] lb_wdata = bg_we ? {bg_data, bg_data} : ld_lb_we ? ld_lb_data : {pt_data, pt_data};
    wire [8:0] lb_ra = mix_busy ? mix_raddr : st_raddr;
    zm_video_sdpram #(.AW(9), .DW(32)) u_lb_lo (.clk(clk), .we({4{bg_we || ld_lb_we || pt_lo}}),
        .waddr(lb_waddr), .wdata(lb_wdata[31:0]), .raddr(lb_ra), .rdata(lb_rdata[31:0]));
    zm_video_sdpram #(.AW(9), .DW(32)) u_lb_hi (.clk(clk), .we({4{bg_we || ld_lb_we || pt_hi}}),
        .waddr(lb_waddr), .wdata(lb_wdata[63:32]), .raddr(lb_ra), .rdata(lb_rdata[63:32]));

    // --- pass sequencing ---
    wire start_bg, start_pl, start_mix, mix_first, fetching, ld_start, ld_pfb, ld_d, st_start, st_pfb, st_d;
    wire bg_done, pl_done, mix_done, ld_done, st_done;
    wire [31:0] pfb_addr, d_addr;
    zm_video_pass u_pass (
        .clk(clk), .rst(rst), .take(take), .op(cmd_op), .line(cmd_line), .mix(cmd_mix), .first(cmd_first),
        .vbase(vbase), .dbase(dbase), .pfb_addr(pfb_addr), .d_addr(d_addr), .busy(busy), .fetching(fetching),
        .start_bg(start_bg), .start_pl(start_pl), .start_mix(start_mix), .mix_first(mix_first),
        .bg_done(bg_done), .pl_done(pl_done), .mix_done(mix_done), .ld_start(ld_start), .ld_pfb(ld_pfb),
        .ld_d(ld_d), .ld_done(ld_done), .st_start(st_start), .st_pfb(st_pfb), .st_d(st_d), .st_done(st_done),
        .lb_painted(pt_lo || pt_hi), .painted(painted), .done(pass_done));

    // --- background pass ---
    reg [8:0] line;
    always @(posedge clk) if (take) line <= cmd_line;
    zm_video_bg u_bg (
        .clk(clk), .rst(rst), .start(start_bg), .last_line(line == ZM_RASTER_HEIGHT - 1),
        .bg(regs[ZM_REG_BACKGROUND * 8 +: 32]), .count(regs[ZM_REG_BEAM_COUNT * 8 +: 16]),
        .beam_raddr(beam_raddr), .beam_rdata(beam_rdata), .lb_we(bg_we), .lb_addr(bg_addr),
        .lb_data(bg_data), .done(bg_done), .beam_upd(beam_upd), .beam_bg(beam_bg),
        .beam_drops(beam_drops), .frame_inc(frame_inc));

    // --- plane pass: its fetch and the row loads share the read port, by phase ---
    wire pl_rd_valid, rw_rd_valid;
    wire [31:0] pl_rd_addr, rw_rd_addr;
    wire [9:0] pl_rd_len, rw_rd_len;
    assign rd_req_valid = fetching ? pl_rd_valid : rw_rd_valid;
    assign rd_req_addr = fetching ? vbase + pl_rd_addr : rw_rd_addr;
    assign rd_req_len = fetching ? pl_rd_len : rw_rd_len;
    zm_video_planepath u_pp (
        .clk(clk), .rst(rst), .latch(latch), .start(start_pl), .plane(take ? cmd_plane : plane),
        .py(line), .regs(regs), .done(pl_done),
        .rd_req_valid(pl_rd_valid), .rd_req_ready(fetching && rd_req_ready), .rd_req_addr(pl_rd_addr),
        .rd_req_len(pl_rd_len), .rd_rsp_valid(fetching && rd_rsp_valid), .rd_rsp_data(rd_rsp_data),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata), .fb_raddr(fb_raddr), .fb_rdata(fb_rdata),
        .pal_raddr(pal_raddr), .pal_rdata(pal_rdata), .lb_we_lo(pt_lo), .lb_we_hi(pt_hi), .lb_addr(pt_addr),
        .lb_data(pt_data), .overflow(overflow));

    // --- row I/O and the plane mixer ---
    zm_video_rowio u_row (
        .clk(clk), .rst(rst), .pfb_addr(pfb_addr), .d_addr(d_addr), .ld_start(ld_start), .ld_pfb(ld_pfb),
        .ld_d(ld_d), .ld_done(ld_done), .rd_req_valid(rw_rd_valid), .rd_req_ready(!fetching && rd_req_ready),
        .rd_req_addr(rw_rd_addr), .rd_req_len(rw_rd_len), .rd_rsp_valid(!fetching && rd_rsp_valid),
        .rd_rsp_data(rd_rsp_data), .lb_we(ld_lb_we), .acc_we(ld_acc_we), .ld_addr(ld_addr),
        .ld_lb_data(ld_lb_data), .ld_acc_data(ld_acc_data), .st_start(st_start), .st_pfb(st_pfb), .st_d(st_d),
        .st_done(st_done), .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr),
        .wr_req_len(wr_req_len), .wr_dat_valid(wr_dat_valid), .wr_dat_ready(wr_dat_ready), .wr_dat(wr_dat),
        .wr_busy(wr_busy), .st_raddr(st_raddr), .st_lb_rdata(lb_rdata), .st_acc_rdata(acc_rdata));
    zm_video_mix u_mix (
        .clk(clk), .rst(rst), .start(start_mix), .first(mix_first), .busy(mix_busy), .done(mix_done),
        .lb_raddr(mix_raddr), .lb_rdata(lb_rdata), .ld_we(ld_acc_we), .ld_addr(ld_addr), .ld_data(ld_acc_data),
        .st_raddr(st_raddr), .st_rdata(acc_rdata));
endmodule

`default_nettype wire
