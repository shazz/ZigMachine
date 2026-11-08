// TRIANGLE sequencer: deterministic odd-even scanline fill, the arithmetic of
// machine/blitter_ops.zig doTriangle/crossSpan. The model, for each scanline y, takes each edge
// with ay < by and ay <= y < by (half-open) at x = ax + floor((bx-ax) * (y-ay) / (by-ay)) and
// fills from the least such x to the greatest, cut to the clip.
// Here the vertices are ranked by y once (top, mid, bot): on any line exactly two edges are live,
// the long one (top, bot) and a short one, (top, mid) above mid and (mid, bot) from mid down,
// and a horizontal edge never is. Each live edge is a Bresenham walker on the floor itself
// (zm_blit_twalk): no divider, no multiplier. A visible row costs a few clocks plus its pixels
// (the edges' x steps run during the span), where v1 divided three times a row (~111 clocks).
// The trade: an edge whose top is above the first visible row is walked down to it, two clocks
// a hidden row (a vertex 3000 rows up: ~12,000 clocks; at -32768: ~130,000, v1 ~22,000).
// Edge setup (2026-11-08): PICK registers the edge's vertices (vertex mux -> subtract in one
// clock missed 100 MHz on the board in v1), EDGE dx, dy, the hidden rows t and `dead` (a short
// edge that ends above the row: (mid, bot) takes over; a flat one is never walked), INI loads
// the walker, PREA/PREB walk the t hidden rows.
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
    localparam [3:0] IDLE = 0, PICK = 1, EDGE = 2, INI = 3, PREA = 4, PREB = 5, LINE = 6, MINMAX = 7, SPAN = 8,
                     PIX = 9, NEXTY = 10;
    reg [3:0] st;
    reg [1:0] sid;                  // the edge being set up: 0 long (top, bot), 1 (top, mid), 2 (mid, bot)
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

    // edge setup: PICK registers the vertices, EDGE the differences, INI loads the walker, PREA/PREB
    // walk it from its top row down to the first visible one (t rows)
    reg signed [15:0] ax, ay, bx, by, l_by, s_by;
    reg [15:0] dy, t;
    reg signed [16:0] e_dx;
    reg dead;
    wire signed [16:0] dx = {bx[15], bx} - {ax[15], ax};
    wire signed [16:0] ys = {7'd0, y}, lb = {l_by[15], l_by}, sb = {s_by[15], s_by};

    wire to_s = sid != 2'd0;
    wire w_clr = st == PICK, w_ini = st == INI, w_sa = st == SPAN || st == PREA && !dead && t != 16'd0;
    wire w_sb = st == PREB || st == PIX || st == NEXTY;
    wire cy_l, cy_s;                    // a walker moved its x this clock
    wire signed [15:0] xa, xb;          // the long edge's x, the short edge's
    zm_blit_twalk wl (.clk(clk), .clr(w_clr && !to_s), .ini(w_ini && !to_s), .kax(ax), .kdx(e_dx), .kdy(dy),
        .sa(w_sa && (st == SPAN || !to_s)), .sb(w_sb && (st != PREB || !to_s)), .carry(cy_l), .x(xa));
    zm_blit_twalk ws (.clk(clk), .clr(w_clr && to_s), .ini(w_ini && to_s), .kax(ax), .kdx(e_dx), .kdy(dy),
        .sa(w_sa && (st == SPAN || to_s)), .sb(w_sb && (st != PREB || to_s)), .carry(cy_s), .x(xb));

    assign px_valid = st == PIX && x <= xend;
    assign px_x = x;
    assign px_y = {8'd0, y};

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (go) begin
                y <= ey0[9:0]; sid <= 2'd0;
                i_top <= who(2'd0, rk0, rk1); i_mid <= who(2'd1, rk0, rk1); i_bot <= who(2'd2, rk0, rk1);
                if (ey0 >= ey1) done <= 1'b1;
                else st <= PICK;
            end
            PICK: begin
                ax <= pickv(ia, x0[15:0], x1[15:0], x2[15:0]); ay <= pickv(ia, y0[15:0], y1[15:0], y2[15:0]);
                bx <= pickv(ib, x0[15:0], x1[15:0], x2[15:0]); by <= pickv(ib, y0[15:0], y1[15:0], y2[15:0]);
                st <= EDGE;
            end
            EDGE: begin
                e_dx <= dx; dy <= by - ay;
                t <= {6'd0, y} - ay;                  // rows above the first visible one
                dead <= ys >= $signed({by[15], by}); // the edge ends above it (the short one: go to (mid, bot))
                if (to_s) s_by <= by; else l_by <= by;
                st <= INI;
            end
            INI: st <= PREA;
            PREA: if (dead || t == 16'd0) begin
                    if (sid == 2'd0) begin sid <= 2'd1; st <= PICK; end
                    else if (dead && sid == 2'd1) begin sid <= 2'd2; st <= PICK; end
                    else st <= LINE;
                end else begin t <= t - 16'd1; st <= PREB; end
            PREB: if (!cy_l && !cy_s) st <= PREA;
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
                st <= PIX;
            end
            PIX: begin
                if (x > xend || (px_ready && x == xend)) st <= NEXTY;
                if (px_ready) x <= x + 18'sd1;
            end
            default: if (!cy_l && !cy_s) begin   // NEXTY: the walkers reach the next row (they step during PIX)
                y <= y + 10'd1;
                st <= LINE;
            end
        endcase
    end
endmodule
