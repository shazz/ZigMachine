// The checks machine/blitter.zig makes before it draws, as a short serial walk after `go`:
//   - the clipped box the op can reach (opBox) -> ex0..ey1, which the BLIT/FILL sequencer also
//     loops over: a rectangle, or a LINE's / TRIANGLE's vertices merged one per clock;
//   - destInRegion: D never leaves the video region (an empty box writes nothing);
//   - BLIT only: W,H non-zero, and each used source rectangle inside the region (relative)
//     or inside ONE readable window (SRC_ABS).
// `ok` low means "draw nothing, CYCLES = 0", which is what the Zig machine does for every one
// of its early returns.
// `overlap` (BLIT): a used source may be read after an earlier pixel of the op wrote it, so the
// pixel unit must not read A or B ahead of the earlier writes (zm_blit_px `ordered`). It is
// clear when either holds, per source:
//   - apart: the source span [s_lo, s_lo + (h-1)*stride + w) and the destination box's span
//     [first byte, last byte] share no byte (the box's, not the plane's: a strip copied to rows
//     below or above it in the same plane runs unordered);
//   - the walk never reads behind itself: with one row (h = 1) or the destination's stride,
//     every source byte is its destination byte + delta, one constant; the destination
//     addresses only grow (ascending) or only shrink (DESC), so delta >= 0 ascending (<= 0 DESC)
//     never reads a byte an earlier pixel wrote (a scroll in the direction of the walk).
// The sources go through ONE check unit, A then B (the same window compares, adds and apart
// test twice), and the box through one min/max per axis: the fold of SOC_REVIEW F5.
// Every product is registered a clock before the sums that use them (one clock held a
// multiply, an add and three window compares: -2.5 ns at 100 MHz on the board, 2026-10-10).
// The box is final at state 4, more than three clocks before the core's `go` reaches the
// sequencers: zm_blit_row's setup pipeline (each channel's first row) needs those three.
`default_nettype none
`include "memmap.vh"

module zm_blit_chk (
    input  wire               clk,
    input  wire               go,
    input  wire [7:0]         cmd,
    input  wire               use_a, use_b, abs_src, desc,
    input  wire [31:0]        d_base, a_base, b_base,
    input  wire [15:0]        ds, a_stride, b_stride, w, h,
    input  wire signed [17:0] x0, y0, x1, y1, x2, y2,
    input  wire signed [17:0] cx0, cy0, cx1, cy1,
    output reg                done,
    output reg                ok,
    output reg signed [17:0]  ex0, ey0, ex1, ey1,
    output reg                overlap
);
    localparam [24:0] VIDEO = ZM_HW_VIDEO_BASE, VTOP = ZM_HW_VIDEO_BASE + ZM_REGION_BYTES;
    reg [3:0] st;
    reg sel;                                    // the source being checked: 0 A, 1 B
    reg signed [17:0] bx0, by0, bx1, by1;
    wire is_rect = cmd == ZM_BLIT_CMD_FILL || cmd == ZM_BLIT_CMD_BLIT;
    wire is_poly = cmd == ZM_BLIT_CMD_LINE || cmd == ZM_BLIT_CMD_TRIANGLE;
    // the vertex merged at states 2 and 3: v1, then v2 (a LINE has two vertices: v0 again)
    wire signed [17:0] vx = st == 4'd2 ? x1 : cmd == ZM_BLIT_CMD_TRIANGLE ? x2 : x0;
    wire signed [17:0] vy = st == 4'd2 ? y1 : cmd == ZM_BLIT_CMD_TRIANGLE ? y2 : y0;

    // the destination: products at state 5, spans at 6 (offsets from D_BASE, then linear)
    reg [24:0] p_last, p_first;
    reg signed [35:0] p_org;
    reg [25:0] dlast_q;                         // (ey1-1)*ds + ex1: one past the box's last byte
    reg [24:0] d_lo, d_hi;                      // the box's span, linear
    reg signed [26:0] d_org;                    // the linear address of the rectangle's (x0, y0)
    wire empty = ex1 <= ex0 || ey1 <= ey0;
    wire [8:0] ylast = ey1[8:0] - 9'd1;         // the box is inside a buffer of at most 280 rows
    wire [24:0] d_lin = VIDEO + {3'd0, d_base[21:0]};
    wire dest_ok = empty || (d_base[31:22] == 10'd0 && {4'd0, d_base[21:0]} + dlast_q <= ZM_REGION_BYTES);

    // the source under check
    wire [31:0] s_base = sel ? b_base : a_base;
    wire [15:0] s_str = sel ? b_stride : a_stride;
    wire s_use = sel ? use_b : use_a;
    reg [31:0] prod;                            // (h-1) * stride
    reg [15:0] m_h, m_s;                        // its operands, registered a clock before
    reg [24:0] s_lo, s_hi;                      // the source's span, linear
    reg s_small, s_same;                        // base and product below 2^23; stride as D's or one row
    wire in_video = s_lo >= VIDEO && s_hi <= VTOP;
    wire in_cart = s_lo >= ZM_CART_RAM_BASE && s_hi <= ZM_CART_RAM_TOP;
    wire in_rom = s_lo >= ZM_ROM_RAM_BASE && s_hi <= ZM_ROM_RAM_TOP;
    wire src_ok = s_small && (in_video || (abs_src && (in_cart || in_rom)));
    wire apart = s_hi <= d_lo || d_hi <= s_lo;
    wire signed [26:0] delta = $signed({2'b00, s_lo}) - d_org;
    wire behind_safe = s_same && (desc ? delta <= 27'sd0 : delta >= 27'sd0);
    reg src_acc, ord_acc;

    always @(posedge clk) begin
        done <= 1'b0;
        case (st)
            4'd0: if (go) begin st <= 4'd1; sel <= 1'b0; src_acc <= 1'b1; ord_acc <= 1'b0; end
            4'd1: begin  // opBox: the rectangle, the first vertex, or (other ops) the clip
                bx0 <= is_rect || is_poly ? x0 : cx0;
                by0 <= is_rect || is_poly ? y0 : cy0;
                bx1 <= is_rect ? x0 + $signed({2'd0, w}) : is_poly ? x0 + 18'sd1 : cx1;
                by1 <= is_rect ? y0 + $signed({2'd0, h}) : is_poly ? y0 + 18'sd1 : cy1;
                st <= 4'd2;
            end
            4'd2, 4'd3: begin  // the other vertices, one a clock
                if (is_poly) begin
                    if (vx < bx0) bx0 <= vx;
                    if (vy < by0) by0 <= vy;
                    if (vx >= bx1) bx1 <= vx + 18'sd1;
                    if (vy >= by1) by1 <= vy + 18'sd1;
                end
                st <= st + 4'd1;
            end
            4'd4: begin  // ... cut to the clip
                ex0 <= bx0 > cx0 ? bx0 : cx0;
                ey0 <= by0 > cy0 ? by0 : cy0;
                ex1 <= bx1 < cx1 ? bx1 : cx1;
                ey1 <= by1 < cy1 ? by1 : cy1;
                m_h <= h - 16'd1; m_s <= a_stride;
                st <= 4'd5;
            end
            4'd5: begin  // products
                p_last <= ylast * ds;
                p_first <= ey0[8:0] * ds;
                p_org <= y0 * $signed({2'b00, ds});
                prod <= m_h * m_s;
                st <= 4'd6;
            end
            4'd6: begin  // spans
                dlast_q <= {1'b0, p_last} + {8'd0, ex1[16:0]};
                d_lo <= d_lin + p_first + {8'd0, ex0[16:0]};
                d_hi <= d_lin + p_last + {8'd0, ex1[16:0]};
                d_org <= $signed({2'b00, d_lin}) + p_org[26:0] + {{9{x0[17]}}, x0};
                s_lo <= (abs_src ? 25'd0 : VIDEO) + {2'b00, s_base[22:0]};
                s_hi <= (abs_src ? 25'd0 : VIDEO) + {2'b00, s_base[22:0]} + {2'b00, prod[22:0]} + {9'd0, w};
                s_small <= s_base[31:23] == 9'd0 && prod[31:23] == 9'd0;
                s_same <= h == 16'd1 || s_str == ds;
                st <= 4'd7;
            end
            4'd7: begin  // this source's verdict; then the next source, or the op's
                if (s_use) begin
                    src_acc <= src_acc && src_ok;
                    ord_acc <= ord_acc || !(apart || behind_safe);
                end
                sel <= 1'b1;
                m_s <= b_stride;
                st <= sel ? 4'd8 : 4'd5;
            end
            default: begin
                ok <= dest_ok && (cmd != ZM_BLIT_CMD_BLIT || (w != 16'd0 && h != 16'd0 && src_acc));
                overlap <= ord_acc;
                done <= 1'b1;
                st <= 4'd0;
            end
        endcase
    end
    initial st = 4'd0;
endmodule
