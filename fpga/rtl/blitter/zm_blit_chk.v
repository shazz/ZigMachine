// The checks machine/blitter.zig makes before it draws, in three clocks after `go`:
//   - the clipped box the op can reach (opBox) -> ex0..ey1, which the FILL and BLIT
//     sequencers also loop over;
//   - destInRegion: D never leaves the video region (an empty box writes nothing);
//   - BLIT only: W,H non-zero, and each used source rectangle inside the region (relative)
//     or inside ONE readable window (SRC_ABS).
// `ok` low means "draw nothing, CYCLES = 0", which is what the Zig machine does for
// every one of its early returns.
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
    output reg signed [17:0]  ex0, ey0, ex1, ey1
);
    reg [1:0] st;
    reg signed [17:0] bx0, by0, bx1, by1;
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
    wire dest_ok = empty || (d_base[31:22] == 10'd0 && {4'd0, d_base[21:0]} + dlast <= ZM_REGION_BYTES);

    wire [15:0] hm1 = h - 16'd1;
    // Everything a source may touch is below 2^23, so a base or a (h-1)*stride at or above it fails.
    function src_ok(input [31:0] base, input [15:0] stride);
        reg [31:0] prod;
        reg [24:0] hi;
        begin
            prod = hm1 * stride;
            hi = {2'b00, base[22:0]} + {2'b00, prod[22:0]} + w;
            src_ok = base[31:23] == 9'd0 && prod[31:23] == 9'd0 && (abs_src
                ? ((base >= ZM_CART_RAM_BASE && hi <= ZM_CART_RAM_TOP)
                   || (base >= ZM_HW_VIDEO_BASE && hi <= ZM_HW_VIDEO_BASE + ZM_REGION_BYTES)
                   || (base >= ZM_ROM_RAM_BASE && hi <= ZM_ROM_RAM_TOP))
                : hi <= ZM_REGION_BYTES);
        end
    endfunction
    wire blit_ok = cmd != ZM_BLIT_CMD_BLIT
        || (w != 16'd0 && h != 16'd0 && (!use_a || src_ok(a_base, a_stride)) && (!use_b || src_ok(b_base, b_stride)));

    always @(posedge clk) begin
        done <= 1'b0;
        case (st)
            2'd0: if (go) st <= 2'd1;
            2'd1: begin  // opBox, before the clip
                bx0 <= is_rect ? x0 : is_poly ? minx : cx0;
                by0 <= is_rect ? y0 : is_poly ? miny : cy0;
                bx1 <= is_rect ? x0 + $signed({2'd0, w}) : is_poly ? maxx + 18'sd1 : cx1;
                by1 <= is_rect ? y0 + $signed({2'd0, h}) : is_poly ? maxy + 18'sd1 : cy1;
                st <= 2'd2;
            end
            2'd2: begin  // ... cut to the clip
                ex0 <= bx0 > cx0 ? bx0 : cx0;
                ey0 <= by0 > cy0 ? by0 : cy0;
                ex1 <= bx1 < cx1 ? bx1 : cx1;
                ey1 <= by1 < cy1 ? by1 : cy1;
                st <= 2'd3;
            end
            default: begin
                ok <= dest_ok && blit_ok;
                done <= 1'b1;
                st <= 2'd0;
            end
        endcase
    end
    initial st = 2'd0;
endmodule
