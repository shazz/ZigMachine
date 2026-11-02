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
    input  wire          latch,          // copy the registers into slot `wplane`
    input  wire [1:0]    wplane,         // the slot written: the command's plane on its take
    input  wire [1:0]    plane,          // the slot read: the compositor's registered plane
    input  wire [1023:0] regs,
    input  wire          upd,            // a plane pass ran: store its overscan state
    input  wire [15:0]   upd_seen,
    input  wire          upd_top, upd_bot,
    input  wire          lb_we,          // a copper LBASE (HW 1.10.0): the plane's base from row lb_row
    input  wire [20:0]   lb_val,
    input  wire [8:0]    lb_row,
    output wire [7:0]    mode,
    output wire [31:0]   base,
    output wire [15:0]   stride, hpos, hs, seen,
    output wire [8:0]    lrow,           // the row the base is at (0 from FB_BASE)
    output wire [7:0]    seed,
    output wire          top_open, bot_open
);
`include "zm_video_memmap.vh"

    reg [7:0]  r_mode [0:3];
    reg [31:0] r_base [0:3];
    reg [15:0] r_stride [0:3], r_hpos [0:3], r_hs [0:3], r_seen [0:3];
    reg [7:0]  r_seed [0:3];
    reg [3:0]  r_top = 4'd0, r_bot = 4'd0;
    reg [8:0]  r_lrow [0:3];

    always @(posedge clk) begin
        if (latch) begin
            r_mode[wplane] <= regs[(ZM_REG_FB_MODE + wplane) * 8 +: 8];
            r_base[wplane] <= regs[(ZM_REG_FB_BASE + wplane * 4) * 8 +: 32];
            r_lrow[wplane] <= 9'd0;
            r_stride[wplane] <= regs[(ZM_REG_FB_STRIDE + wplane * 2) * 8 +: 16];
            r_hpos[wplane] <= regs[(ZM_REG_FB_HBL_POS + wplane * 2) * 8 +: 16];
            r_hs[wplane] <= regs[(ZM_REG_HSCROLL + wplane * 2) * 8 +: 16];
            r_seed[wplane] <= regs[ZM_REG_FRAME * 8 +: 8];   // noise uses seed mod 256
            r_seen[wplane] <= regs[ZM_REG_RES_FLICKER * 8 +: 16];
            r_top[wplane] <= 1'b0;
            r_bot[wplane] <= 1'b0;
        end else if (upd) begin
            r_seen[wplane] <= upd_seen;
            if (upd_top) r_top[wplane] <= 1'b1;
            if (upd_bot) r_bot[wplane] <= 1'b1;
        end else if (lb_we) begin
            // LBASE: row r now reads lb_val + (r - lb_row) * stride; the next LATCH restores FB_BASE.
            r_base[wplane] <= {11'd0, lb_val};
            r_lrow[wplane] <= lb_row;
        end
    end

    // Read with the registered plane, written with the take's: the read address no longer hangs on
    // the command's take (cmd_ready -> the plane mux -> every LUT RAM read was comp's worst cone,
    // board_combo7: the copper's d_stop and phys_r, the plane's moved/ncols). Only the take's own
    // clock reads another slot than before, and nothing uses that clock's read: zm_video_plane
    // starts a pass only once its inputs have held four clocks (`moved`, `held`), the copper
    // reads mode/stride in SEL and DEC (busy: no take), the paint in PAINT (busy).
    assign mode = r_mode[plane];
    assign base = r_base[plane];
    assign stride = r_stride[plane];
    assign lrow = r_lrow[plane];
    assign hpos = r_hpos[plane];
    assign hs = r_hs[plane];
    assign seen = r_seen[plane];
    assign seed = r_seed[plane];
    assign top_open = r_top[plane];
    assign bot_open = r_bot[plane];
endmodule

`default_nettype wire
