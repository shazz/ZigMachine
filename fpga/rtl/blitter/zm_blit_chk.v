// The checks machine/blitter.zig makes before it draws, in five clocks after `go`:
//   - the clipped box the op can reach (opBox) -> ex0..ey1, which the FILL and BLIT
//     sequencers also loop over;
//   - destInRegion: D never leaves the video region (an empty box writes nothing);
//   - BLIT only: W,H non-zero, and each used source rectangle inside the region (relative)
//     or inside ONE readable window (SRC_ABS).
// `ok` low means "draw nothing, CYCLES = 0", which is what the Zig machine does for
// every one of its early returns.
// `overlap` (BLIT): a used source rectangle may share a byte with the destination box, so the
// pixel unit must not read A or B ahead of an earlier pixel's write (zm_blit_px `ordered`).
// The test is on spans, conservative: source [base, base + (h-1)*stride + w) against the
// destination [dlin, dlin + (ey1-1)*ds + ex1), both linear and below 2^23 once the checks pass.
// The products are registered a clock before the sums and compares that use them (one
// clock held a 16x16 multiply, a 25-bit add and three window compares: -2.5 ns at 100 MHz
// on the board, Vivado 2026-10-10).
// The box is written at state 2, three clocks before the core's `go` reaches the sequencers:
// zm_blit_row's setup pipeline (each channel's first row) takes exactly those three clocks,
// so a box written later would need `go` later too.
`default_nettype none
`include "memmap.vh"

module zm_blit_chk (
    input  wire               clk,
    input  wire               go,
    input  wire [7:0]         cmd,
    input  wire               use_a, use_b, abs_src,
    input  wire [31:0]        d_base, a_base, b_base,
    input  wire [15:0]        ds, a_stride, b_stride, w, h,
    input  wire signed [17:0] x0, y0, x1, y1, x2, y2,
    input  wire signed [17:0] cx0, cy0, cx1, cy1,
    output reg                done,
    output reg                ok,
    output reg signed [17:0]  ex0, ey0, ex1, ey1,
    output reg                overlap
);
    reg [2:0] st;
    reg signed [17:0] bx0, by0, bx1, by1;
    reg [31:0] prod_a, prod_b;
    reg [25:0] dlast_q;
    reg blit_ok_q;
    reg [23:0] a_hi, b_hi;   // the sources' exclusive ends, linear
    wire is_rect = cmd == ZM_BLIT_CMD_FILL || cmd == ZM_BLIT_CMD_BLIT;
    wire is_poly = cmd == ZM_BLIT_CMD_LINE || cmd == ZM_BLIT_CMD_TRIANGLE;
    wire signed [17:0] vx2 = cmd == ZM_BLIT_CMD_TRIANGLE ? x2 : x0;  // a LINE has two vertices
    wire signed [17:0] vy2 = cmd == ZM_BLIT_CMD_TRIANGLE ? y2 : y0;
    wire signed [17:0] minx = x0 < x1 ? (x0 < vx2 ? x0 : vx2) : (x1 < vx2 ? x1 : vx2);
    wire signed [17:0] maxx = x0 > x1 ? (x0 > vx2 ? x0 : vx2) : (x1 > vx2 ? x1 : vx2);
    wire signed [17:0] miny = y0 < y1 ? (y0 < vy2 ? y0 : vy2) : (y1 < vy2 ? y1 : vy2);
    wire signed [17:0] maxy = y0 > y1 ? (y0 > vy2 ? y0 : vy2) : (y1 > vy2 ? y1 : vy2);

    wire empty = ex1 <= ex0 || ey1 <= ey0;
    // The box is inside the buffer (at most 280 rows), so the last byte is below 2^26; a D_BASE
    // above 2^22 is out of the region whatever the box.
    wire [8:0]  ylast = ey1[8:0] - 9'd1;
    wire [25:0] dlast = ylast * ds + ex1[16:0];
    wire dest_ok = empty || (d_base[31:22] == 10'd0 && {4'd0, d_base[21:0]} + dlast_q <= ZM_REGION_BYTES);

    wire [15:0] hm1 = h - 16'd1;
    // Everything a source may touch is below 2^23, so a base or a (h-1)*stride at or above it fails.
    function src_ok(input [31:0] base, input [31:0] prod);   // prod = (h-1) * stride, registered
        reg [24:0] hi;
        begin
            hi = {2'b00, base[22:0]} + {2'b00, prod[22:0]} + w;
            src_ok = base[31:23] == 9'd0 && prod[31:23] == 9'd0 && (abs_src
                ? ((base >= ZM_CART_RAM_BASE && hi <= ZM_CART_RAM_TOP)
                   || (base >= ZM_HW_VIDEO_BASE && hi <= ZM_HW_VIDEO_BASE + ZM_REGION_BYTES)
                   || (base >= ZM_ROM_RAM_BASE && hi <= ZM_ROM_RAM_TOP))
                : hi <= ZM_REGION_BYTES);
        end
    endfunction
    wire blit_ok = cmd != ZM_BLIT_CMD_BLIT
        || (w != 16'd0 && h != 16'd0 && (!use_a || src_ok(a_base, prod_a)) && (!use_b || src_ok(b_base, prod_b)));

    wire [22:0] a_lin = abs_src ? a_base[22:0] : ZM_HW_VIDEO_BASE + a_base[22:0];
    wire [22:0] b_lin = abs_src ? b_base[22:0] : ZM_HW_VIDEO_BASE + b_base[22:0];
    wire [22:0] d_lin = ZM_HW_VIDEO_BASE + d_base[22:0];
    wire [23:0] d_hi = {1'b0, d_lin} + {1'b0, dlast_q[22:0]};
    function apart(input [22:0] lo, input [23:0] hi);  // [lo, hi) and the destination share no byte
        apart = hi <= {1'b0, d_lin} || d_hi <= {1'b0, lo};
    endfunction

    always @(posedge clk) begin
        done <= 1'b0;
        case (st)
            3'd0: if (go) st <= 3'd1;
            3'd1: begin  // opBox, before the clip; the sources' extents
                prod_a <= hm1 * a_stride;
                prod_b <= hm1 * b_stride;
                bx0 <= is_rect ? x0 : is_poly ? minx : cx0;
                by0 <= is_rect ? y0 : is_poly ? miny : cy0;
                bx1 <= is_rect ? x0 + $signed({2'd0, w}) : is_poly ? maxx + 18'sd1 : cx1;
                by1 <= is_rect ? y0 + $signed({2'd0, h}) : is_poly ? maxy + 18'sd1 : cy1;
                st <= 3'd2;
            end
            3'd2: begin  // ... cut to the clip; the sources checked
                ex0 <= bx0 > cx0 ? bx0 : cx0;
                ey0 <= by0 > cy0 ? by0 : cy0;
                ex1 <= bx1 < cx1 ? bx1 : cx1;
                ey1 <= by1 < cy1 ? by1 : cy1;
                blit_ok_q <= blit_ok;
                st <= 3'd3;
            end
            3'd3: begin  // the destination's last byte; the sources' ends
                dlast_q <= dlast;
                a_hi <= {1'b0, a_lin} + {1'b0, prod_a[22:0]} + {8'd0, w};
                b_hi <= {1'b0, b_lin} + {1'b0, prod_b[22:0]} + {8'd0, w};
                st <= 3'd4;
            end
            default: begin
                ok <= dest_ok && blit_ok_q;
                overlap <= (use_a && !apart(a_lin, a_hi)) || (use_b && !apart(b_lin, b_hi));
                done <= 1'b1;
                st <= 3'd0;
            end
        endcase
    end
    initial st = 3'd0;
endmodule
