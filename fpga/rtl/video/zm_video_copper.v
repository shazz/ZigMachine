// The copper list engine (HW 1.9.0, fpga/review/COPPER_LIST.md): applies a plane's line record to
// its palette (and HSCROLL, and the line's FLICK) before that plane's pass paints the line, exactly
// as machine/copper.zig does in the browser, every rule that stops a list included.
//
//   LATCH plane p    REG_FB_COPPER[p] = v: the list's first HEAD at region OFF_VRAM + 16 v (one beat)
//   PLANE pass p, y  the HEAD says y: one burst of the record and the next HEAD into the fetch
//                    buffer's low half; a PALREF fetches its table into the high half; the words
//                    are applied one at a time, 3 clocks a word (the buffer's read, then a register)
//
// It owns the read port while `busy` (zm_video_comp.v holds the row loads and the plane's fetch
// back); the plane's paint starts after it. A list that breaks a rule stops (live = 0), what its
// record wrote before standing. Addresses are VRAM word indexes here (the list cannot leave VRAM),
// and `rd_req_off` is a region byte offset: the compositor adds vbase.
`default_nettype none

module zm_video_copper (
    input  wire          clk,
    input  wire          rst,
    input  wire          latch,          // a LATCH of `plane`
    input  wire          start,          // a PLANE pass of `plane` over `line` is taken
    input  wire [1:0]    plane,
    input  wire [8:0]    line,
    input  wire [1023:0] regs,
    input  wire [7:0]    mode,           // `plane`'s latched mode and stride (zm_video_latch.v)
    input  wire [15:0]   stride,
    output wire          busy,
    output reg           flick = 1'b0,   // this pass's line FLICKs (until the next start)
    output wire          rd_req_valid,
    input  wire          rd_req_ready,
    output wire [20:0]   rd_req_off,
    output wire [9:0]    rd_req_len,
    input  wire          rd_rsp_valid,
    input  wire [63:0]   rd_rsp_data,
    output wire          fb_we,
    output reg  [7:0]    fb_waddr,
    output wire [7:0]    fb_raddr,
    input  wire [63:0]   fb_rdata,
    output reg           pal_we = 1'b0,
    output reg  [9:0]    pal_waddr,
    output reg  [31:0]   pal_wdata,
    output reg           hs_we = 1'b0,   // HSCROLL of `plane`: register word, enables, data
    output wire [4:0]    hs_word,
    output wire [3:0]    hs_be,
    output wire [31:0]   hs_wdata
);
`include "zm_video_memmap.vh"

    localparam integer VW = ZM_OFF_VRAM / 4;              // VRAM's first word in the region
    localparam [18:0] VWORDS = ZM_VRAM_BYTES / 4;         // VRAM's words: indexes 0 .. VWORDS-1
    localparam [7:0] MAX_BODY = 8'd253;                   // record + next HEAD in 128 beats
    localparam [3:0] IDLE = 0, HEAD = 1, DONE = 2, REC = 3, RD1 = 4, RD2 = 5, DEC = 6, PAL = 7, REFB = 8,
                     SEL = 9, REFD = 10;

    reg [3:0] st = IDLE;
    reg [1:0] p;
    reg [3:0] live = 4'd0;
    reg [8:0] hy [0:3];                   // the next record: its line, its body words, too long
    reg [7:0] hn [0:3];
    reg [3:0] hbig = 4'd0;
    reg [17:0] at [0:3];                  // VRAM word index of the next HEAD
    reg [17:0] q_at;                      // a burst: its first VRAM word, its words
    reg [8:0] q_words;
    reg asked;
    reg [7:0] left;
    reg [7:0] n, i, k, j, first;          // body words, word index, block size and index, entry
    reg ref;                              // the block is a PALREF's (its words in the high half)
    reg [9:0] rword;                      // the buffer word read
    reg [9:0] wbase;                      // buffer word of body word 0
    reg rhalf;
    reg [31:0] wq;                        // the word read, registered
    reg after;                            // the word read is the HEAD after the record
    // The pass's plane's record, copied out of the arrays (SEL), then compared (DONE): two clocks,
    // so no path runs from the LUT RAMs through the adders into the burst.
    reg [8:0] c_hy;
    reg [7:0] c_hn;
    reg c_big, c_cov;
    reg [17:0] c_at, h_at;
    reg [18:0] h_end;
    reg ref_ok_r;
    reg [18:0] t_word_r;

    assign busy = st != IDLE;
    assign rd_req_valid = (st == HEAD || st == REC || st == REFB) && !asked;
    assign rd_req_off = VW * 4 + {1'b0, q_at[17:1], 3'b000};
    wire [8:0] q_span = q_words + {8'd0, q_at[0]} + 9'd1;
    assign rd_req_len = {2'b00, q_span[8:1]};
    assign fb_we = rd_rsp_valid && busy && st != HEAD;
    assign fb_raddr = rword[8:1];
    always @(posedge clk) begin
        rhalf <= rword[0];
        wq <= rhalf ? fb_rdata[63:32] : fb_rdata[31:0];
    end

    wire [3:0] op = wq[31:28];
    wire [8:0] wk = {1'b0, wq[19:12]};
    wire bad_blk = wk == 9'd0 || {1'b0, wq[27:20]} + wk > 9'd256;
    wire [7:0] hs_off = ZM_REG_HSCROLL + {5'd0, p, 1'b0};
    assign hs_word = hs_off[6:2];
    assign hs_be = hs_off[1] ? 4'b1100 : 4'b0011;
    assign hs_wdata = {wq[15:0], wq[15:0]};
    // The lines the plane covers, as zm_video_plane.v reads its mode: every one, or the visible band.
    wire fs = mode == 8'd1 || ((mode == 8'd0 || mode > 8'd4) && stride == ZM_STRIDE_FULLSCREEN);
    wire phys = fs || mode == 8'd4 || (mode == 8'd3 && stride >= ZM_RASTER_WIDTH);
    wire covers = phys || (line >= ZM_RASTER_BORDER_Y && line < ZM_RASTER_BORDER_Y + ZM_HEIGHT);
    // PALREF's table: a word-aligned region offset whose k words lie in VRAM.
    wire [18:0] t_word = wq[20:2] - VW[18:0];
    wire ref_ok = wq[1:0] == 2'd0 && wq[31:21] == 11'd0 && wq[20:2] >= VW[18:0]
                  && t_word + {11'd0, k} <= VWORDS;
    // At a LATCH: the plane's list.
    wire [15:0] l_v = regs[(ZM_REG_FB_COPPER + plane * 2) * 8 +: 16];
    wire [7:0] i_next = i + (ref ? 8'd2 : k + 8'd1);               // after a block
    wire [8:0] rec_beats = ({1'b0, c_hn} + 9'd2 + {8'd0, h_at[0]}) >> 1;
    wire [8:0] ref_beats = ({1'b0, k} + 9'd1 + {8'd0, t_word_r[0]}) >> 1;

    always @(posedge clk) begin
        pal_we <= 1'b0;
        hs_we <= 1'b0;
        if (rd_req_valid && rd_req_ready) asked <= 1'b1;
        if (fb_we) fb_waddr <= fb_waddr + 8'd1;
        if (rd_rsp_valid && busy) left <= left - 8'd1;
        if (rst) begin
            st <= IDLE;
            live <= 4'd0;
        end else case (st)
            IDLE: if (latch) begin
                p <= plane;
                live[plane] <= 1'b0;
                at[plane] <= {l_v, 2'b00};
                if (l_v != 16'd0) begin
                    q_at <= {l_v, 2'b00};
                    q_words <= 9'd1;
                    asked <= 1'b0;
                    left <= 8'd1;
                    st <= HEAD;
                end
            end else if (start) begin
                p <= plane;
                flick <= 1'b0;
                c_hy <= hy[plane];
                c_hn <= hn[plane];
                c_big <= hbig[plane];
                c_at <= at[plane];
                if (live[plane]) st <= SEL;
            end
            SEL: begin                     // the body's first word, and the word past the next HEAD
                h_at <= c_at + 18'd1;
                h_end <= {1'b0, c_at} + {11'd0, c_hn} + 19'd2;
                c_cov <= covers;
                st <= DONE;
            end
            HEAD: if (rd_rsp_valid) begin  // 16-aligned: the beat's low word
                hy[p] <= rd_rsp_data[27:19];
                hn[p] <= rd_rsp_data[7:0];
                hbig[p] <= rd_rsp_data[9:0] > {2'b00, MAX_BODY};
                live[p] <= rd_rsp_data[31:28] == 4'hF;
                st <= IDLE;
            end
            DONE: begin                    // the pass's line `line` against the next record
                n <= c_hn;
                if (c_hy == 9'd511 || c_hy > line) st <= IDLE;
                else if (c_hy < line || !c_cov || c_big || h_end > VWORDS) begin
                    live[p] <= 1'b0;
                    st <= IDLE;
                end else begin
                    q_at <= h_at;
                    q_words <= {1'b0, c_hn} + 9'd1;
                    asked <= 1'b0;
                    left <= rec_beats[7:0];
                    fb_waddr <= 8'd0;
                    wbase <= {9'd0, h_at[0]};
                    i <= 8'd0;
                    k <= 8'd0;
                    ref <= 1'b0;
                    st <= REC;
                end
            end
            REC: if (asked && left == 8'd0) begin
                rword <= wbase;
                after <= n == 8'd0;
                st <= RD1;
            end
            RD1: st <= RD2;                // the buffer's registered read
            RD2: st <= after || k != 8'd0 ? PAL : DEC;   // then wq holds the word
            DEC: begin                     // wq is body word i
                j <= 8'd0;
                if (op == 4'h0 || op == 4'h3 || (op == 4'h2 && wq[27:20] == hs_off)) begin
                    if (op == 4'h3) flick <= 1'b1;
                    if (op == 4'h2) hs_we <= 1'b1;
                    i <= i + 8'd1;
                    rword <= rword + 10'd1;
                    after <= i + 8'd1 == n;
                    st <= RD1;
                end else if ((op == 4'h1 && !bad_blk && {1'b0, i} + wk < {1'b0, n})
                             || (op == 4'h4 && !bad_blk && i + 8'd1 < n)) begin
                    first <= wq[27:20];
                    k <= wq[19:12];
                    ref <= op == 4'h4;     // a PALREF's next word is its table's offset
                    rword <= rword + 10'd1;
                    st <= RD1;
                end else begin
                    live[p] <= 1'b0;
                    st <= IDLE;
                end
            end
            PAL: if (after) begin          // wq: the HEAD after the record
                hy[p] <= wq[27:19];
                hn[p] <= wq[7:0];
                hbig[p] <= wq[9:0] > {2'b00, MAX_BODY};
                at[p] <= h_at + {10'd0, n};
                live[p] <= wq[31:28] == 4'hF;
                st <= IDLE;
            end else if (ref && rword < 10'd256) begin  // wq: the PALREF table's offset
                ref_ok_r <= ref_ok;
                t_word_r <= t_word;
                st <= REFD;
            end else begin                 // wq: palette word j of the block
                pal_we <= 1'b1;
                pal_waddr <= {p, first + j};
                pal_wdata <= wq;
                if (j + 8'd1 != k) begin
                    j <= j + 8'd1;
                    rword <= rword + 10'd1;
                end else begin
                    i <= i_next;
                    rword <= wbase + {2'b00, i_next};
                    after <= i_next == n;
                    k <= 8'd0;
                    ref <= 1'b0;
                end
                st <= RD1;
            end
            REFD: if (!ref_ok_r) begin
                live[p] <= 1'b0;
                st <= IDLE;
            end else begin
                q_at <= t_word_r[17:0];
                q_words <= {1'b0, k};
                asked <= 1'b0;
                left <= ref_beats[7:0];
                fb_waddr <= 8'd128;
                rword <= 10'd256 + {9'd0, t_word_r[0]};
                st <= REFB;
            end
            REFB: if (asked && left == 8'd0) st <= RD1;
            default: st <= IDLE;
        endcase
    end
endmodule

`default_nettype wire
