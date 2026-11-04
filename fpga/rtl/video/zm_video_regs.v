// The video register block (memmap REG_*, region offsets 0x00..0x7F) as the
// compositor sees it. Only the words the compositor reads are stored; the rest
// (HBL ids, RAM high-waters, the arena) belong to other blocks and read as 0.
//
// `regs` is the block flattened little-endian, bit = byte offset * 8 + bit, so a
// field at byte offset O of width W is regs[O*8 +: W] straight from memmap.vh.
//
// The compositor writes three things back, as video.zig does to memory: the
// BEAM line's last colour into BACKGROUND (colour 0 keeps its value into the
// next line on an ST), the drop count, BEAM_COUNT = 0, and FRAME + 1 after the
// last background line. Those win over a CPU write in the same clock.
`default_nettype none

module zm_video_regs (
    input  wire          clk,
    input  wire          cpu_we,
    input  wire [4:0]    cpu_word,       // word index in the block (offset / 4)
    input  wire [3:0]    cpu_be,
    input  wire [31:0]   cpu_wdata,
    input  wire          cop_we,         // the copper list (zm_video_copper.v): a plane's HSCROLL or TC fade byte
    input  wire [4:0]    cop_word,
    input  wire [3:0]    cop_be,
    input  wire [31:0]   cop_wdata,
    input  wire [4:0]    cpu_rword,
    output wire [31:0]   cpu_rdata,      // combinational read-back
    input  wire          beam_upd,       // a BEAM line ended
    input  wire [31:0]   beam_bg,        //   ... on this colour
    input  wire [31:0]   beam_drops,     //   ... rejecting this many writes
    input  wire          frame_inc,      // the last background line ended
    output wire [1023:0] regs
);
`include "zm_video_memmap.vh"

    localparam integer W_RES = ZM_REG_RESOLUTION / 4, W_BG = ZM_REG_BACKGROUND / 4;
    localparam integer W_FRAME = ZM_REG_FRAME / 4, W_FLICK = ZM_REG_RES_FLICKER / 4;
    localparam integer W_BCOUNT = ZM_REG_BEAM_COUNT / 4, W_BDROP = ZM_REG_BEAM_DROPPED / 4;
    localparam integer W_MODE = ZM_REG_FB_MODE / 4;
    // The true-colour fade (HW 1.16.0): TC_FADE and TC_OFS_R/G/B, a word each (four planes' bytes).
    localparam integer W_TCF = ZM_REG_TC_FADE / 4, W_TCR = ZM_REG_TC_OFS_R / 4;
    localparam integer W_TCG = ZM_REG_TC_OFS_G / 4, W_TCB = ZM_REG_TC_OFS_B / 4;
    localparam [31:0] TCW = (32'd1 << W_TCF) | (32'd1 << W_TCR) | (32'd1 << W_TCG) | (32'd1 << W_TCB);
    // Words the compositor reads: one bit per word of the 32-word block.
    localparam [31:0] IMPL = (32'd1 << W_RES) | (32'd1 << W_BG) | (32'd1 << W_FRAME)
        | (32'd1 << W_FLICK) | (32'd1 << W_BCOUNT) | (32'd1 << W_BDROP) | (32'd1 << W_MODE)
        | (32'd3 << (ZM_REG_FB_HBL_POS / 4)) | (32'd3 << (ZM_REG_FB_STRIDE / 4))
        | (32'd3 << (ZM_REG_HSCROLL / 4)) | (32'd15 << (ZM_REG_FB_BASE / 4))
        | (32'd3 << (ZM_REG_FB_COPPER / 4)) | TCW;
    // The words a copper REG may write (the copper checks the offset; this keeps the rest safe).
    localparam [31:0] COPW = (32'd3 << (ZM_REG_HSCROLL / 4)) | TCW;
    // BEAM_COUNT is the low half of its word (0x66..0x67 is free).
    localparam integer BCOUNT_LSB = (ZM_REG_BEAM_COUNT % 4) * 8;

    // One write port, the copper's REG or else the snoop, as the palette's (zm_video_comp.v): the
    // copper writes only between a take and the pass's `painted`, when the sequencer's drain rule
    // keeps the CPU's stores away. A second port on six words was +160 LUT (OOC, HW 1.16.0): every
    // stored bit of them a 2:1 mux.
    wire cop = cop_we && COPW[cop_word];
    wire w_we = cop || cpu_we;
    wire [4:0] w_word = cop ? cop_word : cpu_word;
    wire [3:0] w_be = cop ? cop_be : cpu_be;
    wire [31:0] w_data = cop ? cop_wdata : cpu_wdata;
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : word
            if (IMPL[g]) begin : stored
                reg [31:0] q = 32'd0;
                integer b;
                always @(posedge clk) begin
                    if (w_we && w_word == g)
                        for (b = 0; b < 4; b = b + 1)
                            if (w_be[b]) q[b*8 +: 8] <= w_data[b*8 +: 8];
                    if (beam_upd && g == W_BG) q <= beam_bg;
                    if (beam_upd && g == W_BDROP) q <= q + beam_drops;
                    if (beam_upd && g == W_BCOUNT) q[BCOUNT_LSB +: 16] <= 16'd0;
                    if (frame_inc && g == W_FRAME) q <= q + 32'd1;
                end
                assign regs[g*32 +: 32] = q;
            end else begin : absent
                assign regs[g*32 +: 32] = 32'd0;
            end
        end
    endgenerate

    // The read-back answers only the words the firmware reads (fpga/cycles/vseq.c copy_back:
    // BACKGROUND, BEAM_DROPPED, BEAM_COUNT, FRAME; vseq_group.c vseq_copper_end: HSCROLL x2 and,
    // since 1.16.0, the four TC fade words a copper REG may have written; the
    // testbench's replay reads the first four): every other word reads 0. A 32:1 mux of 32 bits
    // was -138 LUT (OOC, the true-colour study, fpga/review/TRUECOLOR_PLANE.md "payer 1").
    localparam integer W_HS0 = ZM_REG_HSCROLL / 4, W_HS1 = ZM_REG_HSCROLL / 4 + 1;
    localparam [4:0] C_BG = W_BG, C_FRAME = W_FRAME, C_HS0 = W_HS0, C_HS1 = W_HS1, C_BCOUNT = W_BCOUNT, C_BDROP = W_BDROP;
    localparam [4:0] C_TCF = W_TCF, C_TCR = W_TCR, C_TCG = W_TCG, C_TCB = W_TCB;
    reg [31:0] rd;
    always @(*) case (cpu_rword)
        C_BG:     rd = regs[W_BG * 32 +: 32];
        C_FRAME:  rd = regs[W_FRAME * 32 +: 32];
        C_HS0:    rd = regs[W_HS0 * 32 +: 32];
        C_HS1:    rd = regs[W_HS1 * 32 +: 32];
        C_BCOUNT: rd = regs[W_BCOUNT * 32 +: 32];
        C_BDROP:  rd = regs[W_BDROP * 32 +: 32];
        C_TCF:    rd = regs[W_TCF * 32 +: 32];
        C_TCR:    rd = regs[W_TCR * 32 +: 32];
        C_TCG:    rd = regs[W_TCG * 32 +: 32];
        C_TCB:    rd = regs[W_TCB * 32 +: 32];
        default:       rd = 32'd0;
    endcase
    assign cpu_rdata = rd;
endmodule

`default_nettype wire
