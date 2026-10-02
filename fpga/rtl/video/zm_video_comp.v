// ZigMachine video compositor: builds one 800-pixel raster line at a time in a
// line buffer, from the register block, the 4 palettes, the BEAM table and the
// planes' framebuffers, exactly as machine/video.zig builds that line of the PFB.
//
// A line is a sequence of PASSES, each started by a command:
//   op 0 BG     paint the line from BACKGROUND / the BEAM table   (video.zig clear)
//   op 1 PLANE  composite plane `cmd_plane` over it               (renderPlane)
//   op 2 LATCH  latch plane `cmd_plane`'s frame registers         (top of renderPlane)
// A plane pass overwrites what it covers and leaves the rest, so after the BG
// pass and the passes of the enabled planes 0..p, the line buffer is row
// `cmd_line` of the PFB as the wasm machine leaves it after hwRenderPlane(p).
// Between passes is where the HBL handlers run: the sequencer (the testbench
// today, the HBL interrupt controller on the board) lets the CPU write
// registers and palettes through the CPU port before it issues the next pass.
//
// A pass taken with `cmd_mix` is then folded into the browser's picture of the
// line (zm_video_mix.v): one per enabled plane, or the BG pass alone when no
// plane is enabled. `cmd_last` marks the line's final pass: its sweep writes
// display buffer `line[0]` once the scanout frees it (`dp_free`), and then
// `line_ready` pulses. The next pass waits for the sweep to START, not end.
//
// Memory is reached only through the read port documented in zm_video_fetch.v.
`default_nettype none

module zm_video_comp (
    input  wire        clk,
    input  wire        rst,
    // CPU write port: region-relative word address (byte offset / 4)
    input  wire        cpu_we,
    input  wire [20:0] cpu_waddr,
    input  wire [3:0]  cpu_be,
    input  wire [31:0] cpu_wdata,
    input  wire [4:0]  cpu_rword,        // register read-back (offset / 4, < 0x20)
    output wire [31:0] cpu_rdata,
    // pass commands
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [1:0]  cmd_op,
    input  wire [1:0]  cmd_plane,
    input  wire [8:0]  cmd_line,
    input  wire        cmd_mix,          // fold this pass into the picture (zm_video_mix.v)
    input  wire        cmd_last,         // ... as the line's last pass
    output wire        pass_done,        // one-clock pulse at the end of a BG/PLANE pass
    // memory read port (zm_video_fetch.v)
    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire [31:0] mem_req_addr,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data,
    // line buffer read port: pair x = raster pixels 2x (low half) and 2x+1
    input  wire [8:0]  lb_raddr,
    output wire [63:0] lb_rdata,
    output wire        overflow,         // sticky: a line was too long to fetch
    // the picture: display buffers {line parity, pair} -> 2 x RGB, in the scanout's clock
    input  wire        dp_clk,
    input  wire [9:0]  dp_raddr,
    output wire [47:0] dp_rdata,
    input  wire [1:0]  dp_free,          // display buffer b may be overwritten
    output reg         line_ready,       // one clock: line `ready_line` is in its buffer
    output reg  [8:0]  ready_line,
    output wire        mix_busy,
    output reg         mix_hazard = 1'b0 // sticky: L rewritten before the sweep read it
);
`include "zm_video_memmap.vh"

    localparam integer PAL_W = ZM_OFF_PAL / 4, BEAM_W = ZM_OFF_BEAM_TABLE / 4;
    wire reg_sel = cpu_waddr < 21'd32;
    wire pal_sel = cpu_waddr >= PAL_W && cpu_waddr < PAL_W + ZM_NB_PLANES * ZM_PAL_ENTRIES;
    wire beam_sel = cpu_waddr >= BEAM_W && cpu_waddr < BEAM_W + ZM_BEAM_MAX;
    wire [20:0] pal_idx = cpu_waddr - PAL_W, beam_idx = cpu_waddr - BEAM_W;

    // --- command sequencing ---
    reg busy = 1'b0, pend = 1'b0;
    reg [1:0] plane;
    reg [8:0] line;
    reg pass_mix, pass_last;
    wire take = cmd_valid && cmd_ready;
    wire bg_done, pl_done;
    assign cmd_ready = !busy && !pend;
    assign pass_done = bg_done || pl_done;
    always @(posedge clk) begin
        if (rst) busy <= 1'b0;
        else if (take && cmd_op != 2'd2) busy <= 1'b1;
        else if (pass_done) busy <= 1'b0;
        if (take) {plane, line, pass_mix, pass_last} <= {cmd_plane, cmd_line, cmd_mix, cmd_last};
    end
    wire start_bg = take && cmd_op == 2'd0, start_pl = take && cmd_op == 2'd1;
    wire latch = take && cmd_op == 2'd2;

    // --- registers ---
    wire [1023:0] regs;
    wire beam_upd, frame_inc;
    wire [31:0] beam_bg, beam_drops;
    zm_video_regs u_regs (
        .clk(clk), .cpu_we(cpu_we && reg_sel), .cpu_word(cpu_waddr[4:0]), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cpu_rword(cpu_rword), .cpu_rdata(cpu_rdata), .beam_upd(beam_upd),
        .beam_bg(beam_bg), .beam_drops(beam_drops), .frame_inc(frame_inc), .regs(regs));

    // --- memories: palettes, BEAM table, fetch buffer, line buffer (two halves) ---
    wire [7:0] pal_raddr, fb_raddr, fb_waddr;
    wire [5:0] beam_raddr;
    wire [31:0] pal_rdata, beam_rdata, fb_rdata, fb_wdata;
    wire fb_we;
    zm_video_sdpram #(.AW(10), .DW(32)) u_pal (.clk(clk), .we(cpu_we && pal_sel ? cpu_be : 4'd0),
        .waddr(pal_idx[9:0]), .wdata(cpu_wdata), .raddr({plane, pal_raddr}), .rdata(pal_rdata));
    zm_video_sdpram #(.AW(6), .DW(32)) u_beam (.clk(clk), .we(cpu_we && beam_sel ? cpu_be : 4'd0),
        .waddr(beam_idx[5:0]), .wdata(cpu_wdata), .raddr(beam_raddr), .rdata(beam_rdata));
    zm_video_sdpram #(.AW(8), .DW(32)) u_fbuf (.clk(clk), .we({4{fb_we}}), .waddr(fb_waddr),
        .wdata(fb_wdata), .raddr(fb_raddr), .rdata(fb_rdata));

    wire bg_we, pt_lo, pt_hi;
    wire [8:0] bg_addr, pt_addr;
    wire [31:0] bg_data, pt_data;
    wire [8:0] lb_waddr = bg_we ? bg_addr : pt_addr;
    wire [31:0] lb_wdata = bg_we ? bg_data : pt_data;
    wire [8:0] mix_raddr, lb_ra = mix_busy ? mix_raddr : lb_raddr;
    zm_video_sdpram #(.AW(9), .DW(32)) u_lb_lo (.clk(clk), .we({4{bg_we || pt_lo}}), .waddr(lb_waddr),
        .wdata(lb_wdata), .raddr(lb_ra), .rdata(lb_rdata[31:0]));
    zm_video_sdpram #(.AW(9), .DW(32)) u_lb_hi (.clk(clk), .we({4{bg_we || pt_hi}}), .waddr(lb_waddr),
        .wdata(lb_wdata), .raddr(lb_ra), .rdata(lb_rdata[63:32]));

    // --- background pass ---
    zm_video_bg u_bg (
        .clk(clk), .rst(rst), .start(start_bg), .last_line(cmd_line == ZM_RASTER_HEIGHT - 1),
        .bg(regs[ZM_REG_BACKGROUND * 8 +: 32]), .count(regs[ZM_REG_BEAM_COUNT * 8 +: 16]),
        .beam_raddr(beam_raddr), .beam_rdata(beam_rdata), .lb_we(bg_we), .lb_addr(bg_addr),
        .lb_data(bg_data), .done(bg_done), .beam_upd(beam_upd), .beam_bg(beam_bg),
        .beam_drops(beam_drops), .frame_inc(frame_inc));

    // --- plane pass ---
    zm_video_planepath u_pp (
        .clk(clk), .rst(rst), .latch(latch), .start(start_pl), .plane(take ? cmd_plane : plane),
        .py(take ? cmd_line : line), .regs(regs), .done(pl_done),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready), .mem_req_addr(mem_req_addr),
        .mem_rsp_valid(mem_rsp_valid), .mem_rsp_data(mem_rsp_data), .fb_we(fb_we), .fb_waddr(fb_waddr),
        .fb_wdata(fb_wdata), .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .pal_raddr(pal_raddr),
        .pal_rdata(pal_rdata), .lb_we_lo(pt_lo), .lb_we_hi(pt_hi), .lb_addr(pt_addr), .lb_data(pt_data),
        .overflow(overflow));

    // --- the plane mixer: a sweep after each pass taken with cmd_mix ---
    reg first = 1'b0, p_first, p_last;
    reg [8:0] p_line;
    wire [8:0] rd_ptr;
    wire mix_done;
    wire mix_go = pend && !mix_busy && (!p_last || dp_free[p_line[0]]);
    reg [8:0] mix_line;
    reg mix_last;
    always @(posedge clk) begin
        line_ready <= mix_done && mix_last && !rst;
        if (start_bg) first <= 1'b1;
        if (rst) pend <= 1'b0;
        else if (pass_done && pass_mix) {pend, p_first, p_last, p_line, first} <= {1'b1, first, pass_last, line, 1'b0};
        else if (mix_go) pend <= 1'b0;
        if (mix_go) {mix_line, mix_last} <= {p_line, p_last};
        if (mix_done) ready_line <= mix_line;
        if (mix_busy && (bg_we || pt_lo || pt_hi) && lb_waddr >= rd_ptr) mix_hazard <= 1'b1;
    end
    zm_video_mix u_mix (
        .clk(clk), .rst(rst), .start(mix_go), .first(p_first), .last(p_last), .dbuf(p_line[0]),
        .busy(mix_busy), .rd_ptr(rd_ptr), .done(mix_done), .lb_raddr(mix_raddr), .lb_rdata(lb_rdata),
        .dp_clk(dp_clk), .dp_raddr(dp_raddr), .dp_rdata(dp_rdata));
endmodule

`default_nettype wire
