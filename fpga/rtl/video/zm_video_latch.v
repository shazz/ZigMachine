// Per-plane frame latches. video.zig reads a plane's mode, screen base, stride,
// HBL position, fullscreen fine scroll and the frame counter ONCE, when that
// plane's frame starts (the top of renderPlane*), and only palettes, HSCROLL in
// scroll mode, RESOLUTION in medium mode and the flicker latch per line. On an
// ST the screen base is latched at VBL the same way. A LATCH command copies the
// registers into the plane's slot; the plane passes then read the slot.
//
// The slot also holds the overscan state video.zig keeps in locals across a
// plane's frame: the last flicker count seen and whether each band is open.
`default_nettype none

module zm_video_latch (
    input  wire          clk,
    input  wire          latch,          // copy the registers into slot `plane`
    input  wire [1:0]    plane,
    input  wire [1023:0] regs,
    input  wire          upd,            // a plane pass ran: store its overscan state
    input  wire [15:0]   upd_seen,
    input  wire          upd_top, upd_bot,
    output wire [7:0]    mode,
    output wire [31:0]   base,
    output wire [15:0]   stride, hpos, hs, seen,
    output wire [7:0]    seed,
    output wire          top_open, bot_open
);
`include "zm_video_memmap.vh"

    reg [7:0]  r_mode [0:3];
    reg [31:0] r_base [0:3];
    reg [15:0] r_stride [0:3], r_hpos [0:3], r_hs [0:3], r_seen [0:3];
    reg [7:0]  r_seed [0:3];
    reg [3:0]  r_top = 4'd0, r_bot = 4'd0;

    always @(posedge clk) begin
        if (latch) begin
            r_mode[plane] <= regs[(ZM_REG_FB_MODE + plane) * 8 +: 8];
            r_base[plane] <= regs[(ZM_REG_FB_BASE + plane * 4) * 8 +: 32];
            r_stride[plane] <= regs[(ZM_REG_FB_STRIDE + plane * 2) * 8 +: 16];
            r_hpos[plane] <= regs[(ZM_REG_FB_HBL_POS + plane * 2) * 8 +: 16];
            r_hs[plane] <= regs[(ZM_REG_HSCROLL + plane * 2) * 8 +: 16];
            r_seed[plane] <= regs[ZM_REG_FRAME * 8 +: 8];   // noise uses seed mod 256
            r_seen[plane] <= regs[ZM_REG_RES_FLICKER * 8 +: 16];
            r_top[plane] <= 1'b0;
            r_bot[plane] <= 1'b0;
        end else if (upd) begin
            r_seen[plane] <= upd_seen;
            if (upd_top) r_top[plane] <= 1'b1;
            if (upd_bot) r_bot[plane] <= 1'b1;
        end
    end

    assign mode = r_mode[plane];
    assign base = r_base[plane];
    assign stride = r_stride[plane];
    assign hpos = r_hpos[plane];
    assign hs = r_hs[plane];
    assign seen = r_seen[plane];
    assign seed = r_seed[plane];
    assign top_open = r_top[plane];
    assign bot_open = r_bot[plane];
endmodule

`default_nettype wire
