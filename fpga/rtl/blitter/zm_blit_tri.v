// TRIANGLE sequencer: deterministic odd-even scanline fill, the arithmetic of
// machine/blitter_ops.zig doTriangle/crossSpan. The model, for each scanline y, takes each edge
// with ay < by and ay <= y < by (half-open) at x = ax + floor((bx-ax) * (y-ay) / (by-ay)) and
// fills from the least such x to the greatest, cut to the clip.
// Here the vertices are ranked by y once (top, mid, bot): on any line exactly two edges are live,
// the long one (top, bot) and a short one, (top, mid) above mid and (mid, bot) from mid down,
// and a horizontal edge never is. Each live edge is an incremental walker (zm_blit_twalk) set up
// with two divides (a sequential 16-clock divider): its step floor-divmod(dx, dy), and its start
// at the first visible line, floor-divmod(dx * t0, dy), t0 = that line - ay (no divide when t0 = 0,
// an edge that starts on screen). A scanline then costs a few clocks plus its pixels, where v1
// divided three times a line (~111 clocks). Edge setup (2026-11-07):
//   PICK: the edge's vertices (registered: vertex mux -> subtract -> DSP in one clock missed
//   100 MHz on the board in v1), EDGE: dx, |dx|, dy, t0, MUL: |dx| * t (the DSP), GO: the divide
//   (or clear it: t = 0), DIV, LD: load the walker, A2: the start step; then the same for t = 1.
// CYCLES counts pixels, not clocks: unchanged.
`default_nettype none

module zm_blit_tri (
    input  wire               clk,
    input  wire               rst,
    input  wire               go,
    input  wire signed [17:0] x0, y0, x1, y1, x2, y2, cx0, cx1, ey0, ey1,
    output wire               px_valid,
    output wire signed [17:0] px_x, px_y,
    input  wire               px_ready,
    output reg                done
);
    localparam [3:0] IDLE = 0, PICK = 1, EDGE = 2, MUL = 3, GO = 4, DIV = 5, LD = 6, A2 = 7, LINE = 8,
                     MINMAX = 9, SPAN = 10, STB = 11, PIX = 12, NEXTY = 13;
    reg [3:0] st;
    reg [1:0] sid;                  // the edge being set up: 0 long (top, bot), 1 (top, mid), 2 (mid, bot)
    reg ph;                         // setup phase: 0 the start (t0), 1 the step (t = 1)
    reg [9:0] y;                    // the scanline: inside the check's box, 0..279
    reg signed [17:0] x, xend;
    reg signed [15:0] xl, xr;

    // rank the vertices by y once (ties in any order: a horizontal edge is never live)
    wire caa = $signed(y1[15:0]) < $signed(y0[15:0]), cb = $signed(y2[15:0]) < $signed(y0[15:0]),
         cc = $signed(y2[15:0]) < $signed(y1[15:0]);
    wire [1:0] rk0 = {1'b0, caa} + {1'b0, cb}, rk1 = {1'b0, !caa} + {1'b0, cc};
    function [1:0] who(input [1:0] k, input [1:0] r0, input [1:0] r1);
        who = r0 == k ? 2'd0 : r1 == k ? 2'd1 : 2'd2;
    endfunction
    reg [1:0] i_top, i_mid, i_bot;
    wire [1:0] ia = sid == 2'd2 ? i_mid : i_top, ib = sid == 2'd1 ? i_mid : i_bot;
    function [15:0] pickv(input [1:0] i, input [15:0] a, input [15:0] b, input [15:0] c);
        pickv = i == 2'd0 ? a : i == 2'd1 ? b : c;
    endfunction

    // edge setup: PICK registers the vertices, EDGE the differences, MUL the product
    reg signed [15:0] ax, ay, bx, by, l_by, s_by;
    reg [15:0] adx, sdy, t;
    reg neg, tz;
    reg [31:0] anum;
    wire signed [16:0] dx = {bx[15], bx} - {ax[15], ax};
    wire div_done;
    wire [15:0] q, r;
    zm_blit_div dv (.clk(clk), .rst(rst), .go(st == GO && !tz), .clr(st == GO && tz), .num(anum), .den(sdy),
        .done(div_done), .q(q), .r(r));
    // floor-divmod from the magnitudes: dx >= 0 (q, r); dx < 0: (-q, 0) when r = 0, else (-q-1, dy-r).
    // The start's quotient comes with ax added (the walker starts from x = 0).
    wire nz = |r, rsel = neg && nz;
    wire [15:0] kq = (ph ? 16'd0 : ax) + (neg ? ~q : q) + {15'd0, neg && !nz};
    wire [15:0] kr = (rsel ? sdy : 16'd0) + (rsel ? ~r : r) + {15'd0, rsel};

    wire w_ld = st == LD, w_sa = st == A2 || st == SPAN, w_sb = st == STB;
    wire to_s = sid != 2'd0;
    wire signed [15:0] xa, xb;          // the long edge's x, the short edge's
    zm_blit_twalk wl (.clk(clk), .clr(st == PICK && !to_s), .ld(w_ld && !to_s), .kq(kq), .kr(kr), .kdy(sdy),
        .sa(w_sa && (st == SPAN || !to_s)), .sb(w_sb), .x(xa));
    zm_blit_twalk ws (.clk(clk), .clr(st == PICK && to_s), .ld(w_ld && to_s), .kq(kq), .kr(kr), .kdy(sdy),
        .sa(w_sa && (st == SPAN || to_s)), .sb(w_sb), .x(xb));

    wire signed [16:0] ys = {7'd0, y}, lb = {l_by[15], l_by}, sb = {s_by[15], s_by};
    assign px_valid = st == PIX && x <= xend;
    assign px_x = x;
    assign px_y = {8'd0, y};

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (go) begin
                y <= ey0[9:0]; sid <= 2'd0; ph <= 1'b0;
                i_top <= who(2'd0, rk0, rk1); i_mid <= who(2'd1, rk0, rk1); i_bot <= who(2'd2, rk0, rk1);
                if (ey0 >= ey1) done <= 1'b1;
                else st <= PICK;
            end
            PICK: begin
                ax <= pickv(ia, x0[15:0], x1[15:0], x2[15:0]); ay <= pickv(ia, y0[15:0], y1[15:0], y2[15:0]);
                bx <= pickv(ib, x0[15:0], x1[15:0], x2[15:0]); by <= pickv(ib, y0[15:0], y1[15:0], y2[15:0]);
                ph <= 1'b0;
                st <= EDGE;
            end
            EDGE: begin
                neg <= dx[16]; adx <= dx[16] ? -dx[15:0] : dx[15:0];
                sdy <= by - ay; t <= {6'd0, y} - ay;
                if (to_s) s_by <= by; else l_by <= by;
                st <= MUL;
            end
            MUL: begin anum <= adx * t; tz <= t == 16'd0; st <= GO; end
            GO: st <= tz ? LD : DIV;
            DIV: if (div_done) st <= LD;
            LD: if (!ph) st <= A2;
                else if (sid == 2'd0) begin sid <= 2'd1; st <= PICK; end
                else st <= LINE;
            A2: begin t <= 16'd1; ph <= 1'b1; st <= MUL; end
            LINE: begin
                if (ys >= lb || y == ey1[9:0]) begin st <= IDLE; done <= 1'b1; end
                else if (sid == 2'd1 && ys >= sb) begin sid <= 2'd2; st <= PICK; end
                else st <= MINMAX;
            end
            MINMAX: begin
                xl <= xa < xb ? xa : xb;
                xr <= xa < xb ? xb : xa;
                st <= SPAN;
            end
            SPAN: begin
                x <= xl > cx0 ? xl : cx0;
                xend <= xr < cx1 - 18'sd1 ? xr : cx1 - 18'sd1;
                st <= STB;
            end
            STB: st <= PIX;
            PIX: begin
                if (x > xend || (px_ready && x == xend)) st <= NEXTY;
                if (px_ready) x <= x + 18'sd1;
            end
            default: begin  // NEXTY
                y <= y + 10'd1;
                st <= LINE;
            end
        endcase
    end
endmodule
