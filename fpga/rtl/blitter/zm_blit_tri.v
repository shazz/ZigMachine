// TRIANGLE sequencer: deterministic odd-even scanline fill, the arithmetic of
// machine/blitter.zig doTriangle/crossSpan. For each scanline y (clipped) and each of the
// three edges (low end first, half-open [ay, by)), x = ax + floor((bx-ax) * (y-ay) / (by-ay))
// with the floor division done by a shared sequential divider; xl/xr are the min/max, and
// the span, cut to the clip, is issued as pixels (COLOR or the halftone pick, combined
// with the destination through MINTERM).
// v1 divides per scanline per edge (~35 clocks each); an incremental edge walk (one divide
// per edge per triangle) would make a small triangle several times faster.
// The edge setup is pipelined over four clocks (PICK: pick + order the vertices; EDGE:
// subtract; MUL: |dxe| * t; GO: start the divide) so that no path runs vertex mux ->
// compare -> subtract -> multiply -> divider in one clock: in one, it missed 100 MHz by
// 4 ns on the board (Vivado, 2026-10-10); with the pick and the subtract in one clock the
// full SoC still missed by 1.0 ns, register -> vertex mux -> compare -> subtract -> the
// DSP's input register (2026-10-11), hence PICK. Likewise the edge's x is registered (MINMAX)
// before the min/max. CYCLES counts pixels, not clocks: unchanged.
`default_nettype none

module zm_blit_tri (
    input  wire               clk,
    input  wire               rst,
    input  wire               go,
    input  wire [7:0]         color, bg, mt,
    input  wire               ht_on, ht_bit,
    input  wire signed [17:0] x0, y0, x1, y1, x2, y2, cx0, cx1, ey0, ey1,
    output wire [3:0]         hx, hy,
    output wire               px_valid,
    output wire signed [17:0] px_x, px_y,
    output wire [7:0]         px_bimm, px_mt,
    input  wire               px_ready,
    output reg                done
);
    localparam [3:0] IDLE = 0, EDGE = 1, DIV = 2, NEXT = 3, SPAN = 4, PIX = 5, NEXTY = 6, MUL = 7, GO = 8, MINMAX = 9,
                     PICK = 10;
    reg [3:0] st;
    reg [1:0] e;
    reg signed [17:0] y, ymax, xl, xr, x, xend;

    // the edge e is v[e] -> v[e+1], ordered so that ay < by
    wire [1:0] eb = e == 2'd2 ? 2'd0 : e + 2'd1;
    wire signed [17:0] pax = e == 0 ? x0 : e == 1 ? x1 : x2, pay = e == 0 ? y0 : e == 1 ? y1 : y2;
    wire signed [17:0] pbx = eb == 0 ? x0 : eb == 1 ? x1 : x2, pby = eb == 0 ? y0 : eb == 1 ? y1 : y2;
    wire swap = pay > pby;
    // PICK registers the ordered edge; EDGE subtracts from those registers
    reg signed [17:0] ax, ay, bx, by;
    wire skip = ay == by || y < ay || y >= by;
    wire signed [17:0] dye = by - ay;
    wire signed [17:0] dxe = bx - ax, t = y - ay;   // |dxe| < 2^16, 0 <= t < 2^16: one DSP48
    wire neg = dxe[17];
    wire [16:0] adx = neg ? -dxe[16:0] : dxe[16:0];
    // EDGE registers the ordered edge, MUL the product, GO starts the divider from registers
    reg signed [17:0] e_ax;
    reg [16:0] e_adx, e_t, e_dye;
    reg e_neg, e_skip;
    reg [33:0] anum;   // |dxe| * t: the numerator's magnitude, 17 x 17 unsigned
    wire div_go = st == GO;
    wire div_done;
    wire [31:0] q;
    wire [16:0] r;
    zm_blit_div dv (.clk(clk), .rst(rst), .go(div_go), .num(anum[31:0]), .den(e_dye), .done(div_done), .q(q), .r(r));
    wire [31:0] up = q + (r != 17'd0);
    wire signed [17:0] xe = e_ax + (e_neg ? -up[17:0] : q[17:0]);
    reg signed [17:0] xe_q;

    // the scanlines: the vertices' y range cut to the clip, which is the check's box (ey0, ey1)
    wire signed [17:0] lo = ey0, hi = ey1 - 18'sd1;

    assign hx = x[3:0];
    assign hy = y[3:0];
    assign px_valid = st == PIX && x <= xend;
    assign px_x = x;
    assign px_y = y;
    assign px_bimm = ht_on ? (ht_bit ? color : bg) : color;
    assign px_mt = mt;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (go) begin
                y <= lo; ymax <= hi; e <= 2'd0; xl <= 18'sh1FFFF; xr <= 18'sh20000;
                if (lo > hi) done <= 1'b1;
                else st <= PICK;
            end
            PICK: begin
                ax <= swap ? pbx : pax; ay <= swap ? pby : pay;
                bx <= swap ? pax : pbx; by <= swap ? pay : pby;
                st <= EDGE;
            end
            EDGE: begin
                e_ax <= ax; e_adx <= adx; e_t <= t[16:0]; e_dye <= dye[16:0]; e_neg <= neg; e_skip <= skip;
                st <= MUL;
            end
            MUL: begin
                anum <= e_adx * e_t;
                st <= e_skip ? NEXT : GO;
            end
            GO: st <= DIV;
            DIV: if (div_done) begin
                xe_q <= xe;
                st <= MINMAX;
            end
            MINMAX: begin
                if (xe_q < xl) xl <= xe_q;
                if (xe_q > xr) xr <= xe_q;
                st <= NEXT;
            end
            NEXT: begin
                e <= e + 2'd1;
                st <= e == 2'd2 ? SPAN : PICK;
            end
            SPAN: begin
                x <= xl > cx0 ? xl : cx0;
                xend <= xr < cx1 - 18'sd1 ? xr : cx1 - 18'sd1;
                st <= xr < xl ? NEXTY : PIX;
            end
            PIX: begin
                if (x > xend || (px_ready && x == xend)) st <= NEXTY;
                if (px_ready) x <= x + 18'sd1;
            end
            default: begin  // NEXTY
                y <= y + 18'sd1; e <= 2'd0; xl <= 18'sh1FFFF; xr <= 18'sh20000;
                if (y == ymax) begin st <= IDLE; done <= 1'b1; end
                else st <= PICK;
            end
        endcase
    end
endmodule
