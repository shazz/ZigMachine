// The texture sequencer of CHISEL v2 (machine/blitter_tex.zig): AFFINE (textured spans from a
// list) and MAP (a box whose every texel comes from a (u, v) map). Its pixels go to the pixel
// unit with the texel's address as channel B and their own destination address.
//
//   zm_blit_tfetch: the list's or the map's words, streamed through the core's aux read port
//                   into a FIFO (both live in cart RAM or the ROM window, which CHISEL never
//                   writes, so these reads never wait for a write);
//   the walker:     AFFINE pops a span (6 words), steps u, v a pixel a clock (a clipped pixel
//                   on the left costs its clock, as LINE's do); MAP pops a word per two pixels;
//   the texel pipe: (U, V) -> TEX_CLIP or the masks -> V * A_STRIDE (a DSP) -> + U + A_BASE,
//                   three registered stages, so no multiply sits before the pixel unit.
`default_nettype none

module zm_blit_tex (
    input  wire               clk,
    input  wire               rst,
    input  wire               go_aff, go_map,
    input  wire [22:0]        a_lin,             // the texture's texel (0, 0)
    input  wire [15:0]        a_stride, umask, vmask, uoff, voff,
    input  wire               tclip,
    input  wire [22:0]        list,              // AFFINE: the span list; MAP: the map's (X0, Y0)
    input  wire [15:0]        nspan, ms,         // AFFINE: spans; MAP: the map's row stride
    input  wire signed [17:0] x0, y0,            // MAP: the rectangle's origin
    input  wire signed [17:0] ex0, ey0, ex1, ey1,// MAP: the clipped box
    input  wire signed [17:0] cx0, cy0, cx1, cy1,// AFFINE: the clip
    input  wire [22:0]        dlin,
    input  wire [15:0]        ds,
    output wire               aux_valid,
    input  wire               aux_ready,
    output wire [22:0]        aux_addr,
    input  wire               aux_rsp_valid,
    input  wire [31:0]        aux_rsp_data,
    output wire               px_valid,
    input  wire               px_ready,
    output wire [22:0]        px_dst, px_baddr,
    output reg                done
);
    reg aff;                                     // the op: AFFINE (1) or MAP (0)
    // ---- the words, in order, from zm_blit_tfetch
    wire q_v;
    wire [31:0] q_w;
    wire q_pop;
    zm_blit_tfetch f (.clk(clk), .rst(rst), .go_aff(go_aff), .go_map(go_map), .list(list), .nspan(nspan),
        .ms(ms), .x0(x0), .y0(y0), .ex0(ex0), .ey0(ey0), .ex1(ex1), .ey1(ey1), .aux_valid(aux_valid),
        .aux_ready(aux_ready), .aux_addr(aux_addr), .rsp_valid(aux_rsp_valid), .rsp_data(aux_rsp_data),
        .q_valid(q_v), .q_word(q_w), .q_pop(q_pop));

    // ---- the texel pipe: t1 (U, V, D) -> t2 (masked, clipped) -> t3 (V * stride) -> out (address)
    wire adv;                                    // the pipe moves (the output is free or taken)
    reg t1v, t2v, t3v, ov;
    reg [15:0] t1u, t1t, t2u;
    reg [15:0] t2v_;
    reg [22:0] t1d, t2d, t3d, od;
    reg [31:0] t3p;
    reg [15:0] t3u;
    reg [22:0] ob;
    assign adv = !ov || px_ready;
    assign px_valid = ov;
    assign px_dst = od;
    assign px_baddr = ob;
    wire w_emit;                                 // the walker hands a texel to t1 this clock
    wire [15:0] w_u, w_v;
    wire [22:0] w_d;
    always @(posedge clk) begin
        if (rst) begin t1v <= 1'b0; t2v <= 1'b0; t3v <= 1'b0; ov <= 1'b0; end
        else if (adv) begin
            t1v <= w_emit; t1u <= w_u; t1t <= w_v; t1d <= w_d;
            t2v <= t1v && !(tclip && (t1u > umask || t1t > vmask));
            t2u <= t1u & umask; t2v_ <= t1t & vmask; t2d <= t1d;
            t3v <= t2v; t3p <= t2v_ * a_stride; t3u <= t2u; t3d <= t2d;
            ov <= t3v; ob <= a_lin + t3p[22:0] + {7'd0, t3u}; od <= t3d;
        end
    end
    wire pipe_empty = !t1v && !t2v && !t3v && !ov;

    // ---- the walker
    localparam [2:0] IDLE = 0, POP = 1, ROW = 2, WALK = 3, FLUSH = 4;
    reg [2:0] st;
    reg [2:0] k;                                 // AFFINE: the span word being popped
    reg [15:0] left;                             // AFFINE: spans left
    reg signed [17:0] x, xe, y;
    reg [31:0] u, v, du, dv;
    reg [22:0] drow;
    reg [35:0] yprod;
    reg [1:0] rs;                                // ROW: the product's settle clocks
    reg half;                                    // MAP: the entry's half of the head word
    wire signed [17:0] sx0 = {{2{q_w[15]}}, q_w[15:0]}, sx1 = {{2{q_w[31]}}, q_w[31:16]};
    // AFFINE: a pixel left of the clip steps without a texel; past the right edge the span ends
    wire vis = x >= cx0;
    wire span_end = x >= xe;
    wire m_ok = q_v;                             // MAP: the head word is in
    // MAP: the row's first entry is the high half of its word when its byte address has bit 1 set:
    // list + (y - Y0) * ms + 2 * (ex0 - X0), with list and ms even
    wire signed [17:0] yo = y - y0, xo = ex0 - x0;
    wire map_half = list[1] ^ (yo[0] & ms[1]) ^ xo[0];
    assign w_emit = st == WALK && adv && !span_end && (aff ? vis : m_ok);
    assign w_u = aff ? u[31:16] : {8'd0, half ? q_w[23:16] : q_w[7:0]} + uoff;
    assign w_v = aff ? v[31:16] : {8'd0, half ? q_w[31:24] : q_w[15:8]} + voff;
    assign w_d = drow + {{5{x[17]}}, x};
    // MAP pops the head after its high half, or at the row's last pixel; AFFINE pops 6 a span
    assign q_pop = (st == POP && q_v) || (!aff && w_emit && (half || x == xe - 18'sd1));

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (go_aff || go_map) begin
                aff <= go_aff; k <= 3'd0; left <= nspan;
                if (go_aff) st <= nspan == 16'd0 ? FLUSH : POP;
                else if (ex1 <= ex0 || ey1 <= ey0) st <= FLUSH;
                else begin y <= ey0; st <= ROW; rs <= 2'd0; end
            end
            POP: if (q_v) begin  // AFFINE: one span word a clock
                case (k)
                    3'd0: begin x <= sx0; xe <= sx1 < cx1 ? sx1 : cx1; end
                    3'd1: y <= sx0;
                    3'd2: u <= q_w;
                    3'd3: v <= q_w;
                    3'd4: du <= q_w;
                    default: dv <= q_w;
                endcase
                k <= k + 3'd1;
                if (k == 3'd5) begin k <= 3'd0; left <= left - 16'd1; rs <= 2'd0; st <= ROW; end
            end
            ROW: begin  // the row's address: dlin + y * ds, a product a clock behind
                rs <= rs + 2'd1;
                yprod <= y * $signed({2'b00, ds});
                if (rs == 2'd2) begin
                    drow <= dlin + yprod[22:0];
                    if (aff && (y < cy0 || y >= cy1)) st <= left == 16'd0 ? FLUSH : POP;
                    else begin
                        if (!aff) begin x <= ex0; xe <= ex1; half <= map_half; end
                        st <= WALK;
                    end
                end
            end
            WALK: if (span_end) begin
                if (aff) st <= left == 16'd0 ? FLUSH : POP;
                else if (y == ey1 - 18'sd1) st <= FLUSH;
                else begin y <= y + 18'sd1; rs <= 2'd0; st <= ROW; end
            end else if (aff ? (adv || !vis) : w_emit) begin
                x <= x + 18'sd1;
                if (aff) begin u <= u + du; v <= v + dv; end
                else half <= !half;
            end
            default: if (pipe_empty) begin done <= 1'b1; st <= IDLE; end   // FLUSH
        endcase
    end
endmodule
