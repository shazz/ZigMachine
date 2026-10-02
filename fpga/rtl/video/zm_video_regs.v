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
    // Words the compositor reads: one bit per word of the 32-word block.
    localparam [31:0] IMPL = (32'd1 << W_RES) | (32'd1 << W_BG) | (32'd1 << W_FRAME)
        | (32'd1 << W_FLICK) | (32'd1 << W_BCOUNT) | (32'd1 << W_BDROP) | (32'd1 << W_MODE)
        | (32'd3 << (ZM_REG_FB_HBL_POS / 4)) | (32'd3 << (ZM_REG_FB_STRIDE / 4))
        | (32'd3 << (ZM_REG_HSCROLL / 4)) | (32'd15 << (ZM_REG_FB_BASE / 4));
    // BEAM_COUNT is the low half of its word (0x66..0x67 is free).
    localparam integer BCOUNT_LSB = (ZM_REG_BEAM_COUNT % 4) * 8;

    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : word
            if (IMPL[g]) begin : stored
                reg [31:0] q = 32'd0;
                integer b;
                always @(posedge clk) begin
                    if (cpu_we && cpu_word == g)
                        for (b = 0; b < 4; b = b + 1)
                            if (cpu_be[b]) q[b*8 +: 8] <= cpu_wdata[b*8 +: 8];
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

    assign cpu_rdata = regs[cpu_rword*32 +: 32];
endmodule

`default_nettype wire
