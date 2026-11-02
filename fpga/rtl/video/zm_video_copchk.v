// The copper's checks of the word it reads next (zm_video_copper.v), registered with it: the
// fetch buffer's 64-bit beat holds the word in one half (`rhalf`), and each check is made on BOTH
// halves, the half picked after: the buffer's read (a block RAM's clock-to-out) then reaches the
// adders directly, not through the half mux first (comp -0.77 ns on blk_ok, board_combo7).
// The same functions of (word, room, k) as before: a check of the picked half is the picked check.
//   blk_ok     a PALETTE block fits: k != 0, first + k <= 256, k < room (the body words left)
//   ref_blk_ok a PALREF's: k != 0, first + k <= 256, and its offset word is in the body (room > 1)
//   lb_ok      LBASE: bits 27..21 zero and the offset in VRAM
//   ref_ok     a PALREF table: a word-aligned region offset whose k words lie in VRAM
`default_nettype none

module zm_video_copchk (
    input  wire         clk,
    input  wire [63:0]  fb_rdata,
    input  wire         rhalf,
    input  wire [7:0]   room,
    input  wire [7:0]   k,
    output reg  [31:0]  wq,
    output reg          blk_ok, ref_blk_ok, lb_ok, ref_ok,
    output reg  [18:0]  t_word                 // the table's first VRAM word (ref_ok's offset - VW)
);
`include "zm_video_memmap.vh"

    localparam [18:0] VW = ZM_OFF_VRAM / 4;
    localparam [19:0] VEND = ZM_OFF_VRAM / 4 + ZM_VRAM_BYTES / 4;   // VW + VWORDS

    function blk_fits(input [31:0] w);         // k != 0 and first + k <= 256 (9 bits: no wrap)
        blk_fits = w[19:12] != 8'd0 && {1'b0, w[27:20]} + {1'b0, w[19:12]} <= 9'd256;
    endfunction
    // (w - VW) + k <= VWORDS as w <= VW + VWORDS - k: the same test, as w >= VW and
    // w - VW + k < 2^19 (VW = 1088 > 255), so the 19-bit sum the old form compared never wrapped
    // (board_combo7: the subtract then the add after the block RAM, comp -0.83 ns). `lim` is
    // VEND - k a clock late: k moves on a DEC or PAL edge, and the one read of ref_ok, a PALREF's
    // offset in PAL, is the check made in RD2, two clocks after the DEC that set k.
    reg [19:0] lim;
    always @(posedge clk) lim <= VEND - {12'd0, k};
    function tab_fits(input [31:0] w);
        tab_fits = w[1:0] == 2'd0 && w[31:21] == 11'd0 && w[20:2] >= VW && {1'b0, w[20:2]} <= lim;
    endfunction
    function lb_fits(input [31:0] w);
        lb_fits = w[27:21] == 7'd0 && w[20:0] >= ZM_OFF_VRAM && w[20:0] < ZM_OFF_VRAM + ZM_VRAM_BYTES;
    endfunction

    wire [31:0] lo = fb_rdata[31:0], hi = fb_rdata[63:32];
    wire [31:0] w = rhalf ? hi : lo;
    wire fit_lo = blk_fits(lo), fit_hi = blk_fits(hi);
    wire fit = rhalf ? fit_hi : fit_lo;
    wire room_lo = lo[19:12] < room, room_hi = hi[19:12] < room;
    always @(posedge clk) begin
        wq <= w;
        blk_ok <= rhalf ? fit_hi && room_hi : fit_lo && room_lo;
        ref_blk_ok <= fit && room > 8'd1;
        lb_ok <= rhalf ? lb_fits(hi) : lb_fits(lo);
        ref_ok <= rhalf ? tab_fits(hi) : tab_fits(lo);
        t_word <= w[20:2] - VW;
    end
endmodule

`default_nettype wire
