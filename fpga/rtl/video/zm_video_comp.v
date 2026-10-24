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
//   6 WRITEBACK the four palettes out to the region (zm_video_palwb.v): after a frame whose
//              copper lists wrote entries the CPU never stored (HW 1.9.0)
//   5 CLEAR    hwClear in one clock, when no line of it can differ (no global HBL
//              handler, no BEAM writes): latch BACKGROUND as the fill colour and
//              count the frame as BG line 279 does. The lines are painted later,
//              by the first layer's passes taken with `cmd_fill`.
// A PLANE pass taken with `cmd_mix` also folds the row into the picture, as the
// browser stacks canvas k over canvases 0..k-1 (zm_video_mix.v); `cmd_first`
// marks a line's first fold of the frame; `cmd_fill` (PLANE / MIX) paints the
// line in the CLEAR colour where the pass would load the PFB row BG left. The
// PFB rows go back to the region, where the machine keeps its PFB, so the frame
// is hashable as scene_hash does. `cmd_hold` / `cmd_keep` / `cmd_nopfb` run a
// line through several planes' passes without the rows leaving (zm_video_pass.v).
//
// Between passes is where the HBL handlers run: the sequencer (the cart CPU's
// firmware, fpga/cycles/vseq.c) calls the handler, waits until its stores have
// reached the CPU port (the snoop, soc/zm_video_snoop.py), then issues the pass.
// A pass reads every register and palette entry it needs after it is taken.
//
// Memory is reached through one read port (zm_video_fetch.v) and one write port
// (zm_video_rowio.v), both bursts of 64-bit beats at bus addresses.
`default_nettype none

module zm_video_comp #(
    // What a fully transparent picture pixel shows (zm_video_mix.v): black, the browser's
    // tube too (docs/css/crt.css); soc/zm_video_pipe.py passes it down explicitly.
    parameter [23:0] TUBE = 24'h000000
) (
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
    input  wire        cmd_fill,         // ... over the CLEAR colour, not the PFB row
    input  wire        cmd_hold,         // ... going on from the pass before (no row LOAD)
    input  wire        cmd_keep,         // ... the next pass goes on from this one (no STORE)
    input  wire        cmd_nopfb,        // ... STORE the picture row only
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
    wire busy, cop_busy, wb_busy;
    reg [1:0] plane;
    assign cmd_ready = !busy && !cop_busy && !wb_busy && (!cmd_mix || d_ok);
    wire take = cmd_valid && cmd_ready;
    wire latch = take && cmd_op == 3'd2;
    assign present = take && cmd_op == 3'd4;
    wire clear = take && cmd_op == 3'd5;
    always @(posedge clk) if (take) plane <= cmd_plane;
    reg [31:0] fill_bg;
    reg fill;
    always @(posedge clk) if (take) fill <= cmd_fill && (cmd_op == 3'd1 || cmd_op == 3'd3);

    // --- registers ---
    wire [1023:0] regs;
    wire beam_upd, bg_frame_inc;
    wire frame_inc = bg_frame_inc || clear;
    wire [31:0] beam_bg, beam_drops;
    wire cop_hs_we;
    wire [4:0] cop_hs_word;
    wire [3:0] cop_hs_be;
    wire [31:0] cop_hs_wdata;
    zm_video_regs u_regs (
        .clk(clk), .cpu_we(cpu_we && reg_sel), .cpu_word(cpu_waddr[4:0]), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cop_we(cop_hs_we), .cop_word(cop_hs_word), .cop_be(cop_hs_be),
        .cop_wdata(cop_hs_wdata), .cpu_rword(cpu_rword), .cpu_rdata(cpu_rdata), .beam_upd(beam_upd),
        .beam_bg(beam_bg), .beam_drops(beam_drops), .frame_inc(frame_inc), .regs(regs));
    always @(posedge clk) if (clear) fill_bg <= regs[ZM_REG_BACKGROUND * 8 +: 32];

    // --- memories: palettes, BEAM table, fetch buffer (64-bit beats), line buffer (two halves) ---
    wire [7:0] pal_raddr, fb_raddr, fb_waddr, cop_fb_raddr, cop_fb_waddr;
    wire [5:0] beam_raddr;
    wire [31:0] pal_rdata, beam_rdata, cop_pal_wdata;
    wire [63:0] fb_rdata, fb_wdata;
    wire [9:0] cop_pal_waddr, wb_pal_raddr;
    wire fb_we, cop_fb_we, cop_pal_we;
    // The palette's one write port: the copper's record (it runs only between a take and the
    // pass's `painted`, when the sequencer's drain rule keeps the CPU's stores away), else the snoop.
    zm_video_sdpram #(.AW(10), .DW(32)) u_pal (.clk(clk),
        .we(cop_pal_we ? 4'hF : cpu_we && pal_sel ? cpu_be : 4'd0),
        .waddr(cop_pal_we ? cop_pal_waddr : pal_idx[9:0]), .wdata(cop_pal_we ? cop_pal_wdata : cpu_wdata),
        .raddr(wb_busy ? wb_pal_raddr : {plane, pal_raddr}), .rdata(pal_rdata));
    reg cop_collision = 1'b0;   // sticky: a CPU palette store met a copper write (the break test's)
    always @(posedge clk) if (cop_pal_we && cpu_we && pal_sel) cop_collision <= 1'b1;
    zm_video_sdpram #(.AW(6), .DW(32)) u_beam (.clk(clk), .we(cpu_we && beam_sel ? cpu_be : 4'd0),
        .waddr(beam_idx[5:0]), .wdata(cpu_wdata), .raddr(beam_raddr), .rdata(beam_rdata));
    zm_video_sdpram #(.AW(8), .DW(64)) u_fbuf (.clk(clk), .we({8{fb_we || cop_fb_we}}),
        .waddr(cop_busy ? cop_fb_waddr : fb_waddr), .wdata(rd_rsp_data),   // both fill it from the port
        .raddr(cop_busy ? cop_fb_raddr : fb_raddr), .rdata(fb_rdata));

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
        .fill(cmd_fill), .hold(cmd_hold), .keep(cmd_keep), .nopfb(cmd_nopfb),
        .vbase(vbase), .dbase(dbase), .pfb_addr(pfb_addr), .d_addr(d_addr), .busy(busy), .fetching(fetching),
        .start_bg(start_bg), .start_pl(start_pl), .start_mix(start_mix), .mix_first(mix_first),
        .bg_done(bg_done), .pl_done(pl_done), .mix_done(mix_done), .ld_start(ld_start), .ld_pfb(ld_pfb),
        .ld_d(ld_d), .ld_done(ld_done), .st_start(st_start), .st_pfb(st_pfb), .st_d(st_d), .st_done(st_done),
        .lb_painted(pt_lo || pt_hi), .painted(painted), .done(pass_done));

    // --- background pass ---
    reg [8:0] line;
    always @(posedge clk) if (take) line <= cmd_line;
    zm_video_bg u_bg (
        .clk(clk), .rst(rst), .start(start_bg), .last_line(!fill && line == ZM_RASTER_HEIGHT - 1),
        .bg(fill ? fill_bg : regs[ZM_REG_BACKGROUND * 8 +: 32]),
        .count(fill ? 16'd0 : regs[ZM_REG_BEAM_COUNT * 8 +: 16]),
        .beam_raddr(beam_raddr), .beam_rdata(beam_rdata), .lb_we(bg_we), .lb_addr(bg_addr),
        .lb_data(bg_data), .done(bg_done), .beam_upd(beam_upd), .beam_bg(beam_bg),
        .beam_drops(beam_drops), .frame_inc(bg_frame_inc));

    // --- the copper list: before a PLANE pass paints, it owns the read port (zm_video_copper.v) ---
    wire cop_rd_valid, cop_flick;
    wire [7:0] pl_mode;
    wire [15:0] pl_stride;
    wire [20:0] cop_rd_off;
    wire [9:0] cop_rd_len;
    zm_video_copper u_cop (
        .clk(clk), .rst(rst), .latch(latch), .start(take && cmd_op == 3'd1), .plane(take ? cmd_plane : plane),
        .line(line), .regs(regs), .mode(pl_mode), .stride(pl_stride), .busy(cop_busy), .flick(cop_flick),
        .rd_req_valid(cop_rd_valid), .rd_req_ready(cop_busy && rd_req_ready), .rd_req_off(cop_rd_off),
        .rd_req_len(cop_rd_len), .rd_rsp_valid(cop_busy && rd_rsp_valid), .rd_rsp_data(rd_rsp_data),
        .fb_we(cop_fb_we), .fb_waddr(cop_fb_waddr), .fb_raddr(cop_fb_raddr),
        .fb_rdata(fb_rdata), .pal_we(cop_pal_we), .pal_waddr(cop_pal_waddr), .pal_wdata(cop_pal_wdata),
        .hs_we(cop_hs_we), .hs_word(cop_hs_word), .hs_be(cop_hs_be), .hs_wdata(cop_hs_wdata));
    // The plane's paint waits for the copper: a start held while it runs.
    reg pl_pend = 1'b0;
    wire pl_go = (start_pl || pl_pend) && !cop_busy;
    always @(posedge clk) pl_pend <= !rst && (start_pl || pl_pend) && cop_busy;

    // --- plane pass: its fetch and the row loads share the read port, by phase (the copper first) ---
    wire pl_rd_valid, rw_rd_valid;
    wire [31:0] pl_rd_addr, rw_rd_addr;
    wire [9:0] pl_rd_len, rw_rd_len;
    assign rd_req_valid = cop_busy ? cop_rd_valid : fetching ? pl_rd_valid : rw_rd_valid;
    // One vbase adder for the two region-relative clients.
    wire [31:0] rd_off = cop_busy ? {11'd0, cop_rd_off} : pl_rd_addr;
    assign rd_req_addr = cop_busy || fetching ? vbase + rd_off : rw_rd_addr;
    assign rd_req_len = cop_busy ? cop_rd_len : fetching ? pl_rd_len : rw_rd_len;
    zm_video_planepath u_pp (
        .clk(clk), .rst(rst), .latch(latch), .start(pl_go), .plane(take ? cmd_plane : plane),
        .py(line), .regs(regs), .cop_flick(cop_flick), .lmode(pl_mode), .lstride(pl_stride), .done(pl_done),
        .rd_req_valid(pl_rd_valid), .rd_req_ready(!cop_busy && fetching && rd_req_ready), .rd_req_addr(pl_rd_addr),
        .rd_req_len(pl_rd_len), .rd_rsp_valid(!cop_busy && fetching && rd_rsp_valid), .rd_rsp_data(rd_rsp_data),
        .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata), .fb_raddr(fb_raddr), .fb_rdata(fb_rdata),
        .pal_raddr(pal_raddr), .pal_rdata(pal_rdata), .lb_we_lo(pt_lo), .lb_we_hi(pt_hi), .lb_addr(pt_addr),
        .lb_data(pt_data), .overflow(overflow));

    // --- row I/O and the plane mixer ---
    // --- WRITEBACK: the palettes out through the write port, which nothing else uses then ---
    wire wb_req_valid, wb_dat_valid, rw_req_valid, rw_dat_valid;
    wire [31:0] wb_req_addr, rw_req_addr;
    wire [9:0] wb_req_len, rw_req_len;
    wire [63:0] wb_dat, rw_dat;
    zm_video_palwb u_wb (
        .clk(clk), .rst(rst), .start(take && cmd_op == 3'd6), .vbase(vbase), .busy(wb_busy),
        .pal_raddr(wb_pal_raddr), .pal_rdata(pal_rdata), .wr_req_valid(wb_req_valid),
        .wr_req_ready(wb_busy && wr_req_ready), .wr_req_addr(wb_req_addr), .wr_req_len(wb_req_len),
        .wr_dat_valid(wb_dat_valid), .wr_dat_ready(wb_busy && wr_dat_ready), .wr_dat(wb_dat), .wr_busy(wr_busy));
    assign wr_req_valid = wb_busy ? wb_req_valid : rw_req_valid;
    assign wr_req_addr = wb_busy ? wb_req_addr : rw_req_addr;
    assign wr_req_len = wb_busy ? wb_req_len : rw_req_len;
    assign wr_dat_valid = wb_busy ? wb_dat_valid : rw_dat_valid;
    assign wr_dat = wb_busy ? wb_dat : rw_dat;

    zm_video_rowio u_row (
        .clk(clk), .rst(rst), .pfb_addr(pfb_addr), .d_addr(d_addr), .ld_start(ld_start), .ld_pfb(ld_pfb),
        .ld_d(ld_d), .ld_done(ld_done), .rd_req_valid(rw_rd_valid), .rd_req_ready(!cop_busy && !fetching && rd_req_ready),
        .rd_req_addr(rw_rd_addr), .rd_req_len(rw_rd_len), .rd_rsp_valid(!cop_busy && !fetching && rd_rsp_valid),
        .rd_rsp_data(rd_rsp_data), .lb_we(ld_lb_we), .acc_we(ld_acc_we), .ld_addr(ld_addr),
        .ld_lb_data(ld_lb_data), .ld_acc_data(ld_acc_data), .st_start(st_start), .st_pfb(st_pfb), .st_d(st_d),
        .st_done(st_done), .wr_req_valid(rw_req_valid), .wr_req_ready(!wb_busy && wr_req_ready),
        .wr_req_addr(rw_req_addr), .wr_req_len(rw_req_len), .wr_dat_valid(rw_dat_valid),
        .wr_dat_ready(!wb_busy && wr_dat_ready), .wr_dat(rw_dat),
        .wr_busy(wr_busy), .st_raddr(st_raddr), .st_lb_rdata(lb_rdata), .st_acc_rdata(acc_rdata));
    zm_video_mix #(.TUBE(TUBE)) u_mix (
        .clk(clk), .rst(rst), .start(start_mix), .first(mix_first), .busy(mix_busy), .done(mix_done),
        .lb_raddr(mix_raddr), .lb_rdata(lb_rdata), .ld_we(ld_acc_we), .ld_addr(ld_addr), .ld_data(ld_acc_data),
        .st_raddr(st_raddr), .st_rdata(acc_rdata));
endmodule

`default_nettype wire
