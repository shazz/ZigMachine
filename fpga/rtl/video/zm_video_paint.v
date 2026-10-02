// Painter: turns one fetched plane line into line-buffer writes, one column a
// clock, through a 3-stage pipeline:
//   0  column c -> byte index -> fetch-buffer read     (and the overscan choice)
//   1  byte -> palette index (fetched, or overscan noise) -> palette read
//   2  palette RGBA -> line buffer
// A column is one low-res pixel written as a doubled pair, or one medium pixel
// (`single`) written into one half of a pair. Columns map to the raster from
// `dst0` (raster pixels). Fullscreen (`wrap`) reads source byte (c + s0) mod
// stride, as video.zig's `(lx + hs) % stride`.
//
// Overscan (`ov`), video.zig renderPlaneOverscan row for row: the 320-wide window
// of a visible line is always drawn; outside it a column comes from the buffer
// when its border is open (`band_open` in a band, `hit` on a visible line),
// is noise when the line flickered but missed, and is not written otherwise.
`default_nettype none

module zm_video_paint (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [9:0]  ncols,
    input  wire [1:0]  align,
    input  wire        single,
    input  wire [9:0]  dst0,
    input  wire        wrap,
    input  wire [15:0] stride,
    input  wire [15:0] s0,
    input  wire        ov, band, band_open, hit, flick,
    input  wire [7:0]  nbase,          // noise index of column 0: y*101 + seed*7
    output wire [7:0]  fb_raddr,
    input  wire [31:0] fb_rdata,
    output wire [7:0]  pal_raddr,
    input  wire [31:0] pal_rdata,
    output reg         lb_we_lo, lb_we_hi,
    output reg  [8:0]  lb_addr,
    output reg  [31:0] lb_data,
    output reg         done
);
`include "zm_video_memmap.vh"

    localparam integer L = ZM_HORIZONTAL_BORDERS_WIDTH, R = L + ZM_WIDTH;
    reg        run = 1'b0;
    reg [9:0]  c;
    reg [15:0] s;
    reg [7:0]  noise;                       // noise index of column c (+37 a column)
    wire [10:0] bi = {9'd0, align} + (wrap ? s[10:0] : {1'b0, c});
    wire inner = !band && c >= L && c < R;
    wire open_c = band ? band_open : hit;
    wire wr0 = !ov || inner || open_c || flick;
    wire nz0 = ov && !(inner || open_c);
    wire [9:0] px0 = single ? dst0 + c : {dst0[9:1] + c[8:0], 1'b0};
    assign fb_raddr = bi[9:2];

    // Stage registers: 1 = fetch-buffer data valid, 2 = palette data valid.
    reg        v1, wr1, nz1, v2, wr2;
    reg [1:0]  sel1;
    reg [7:0]  n1;
    reg [9:0]  px1, px2;
    reg        single1, single2;
    wire [7:0] byte1 = fb_rdata[sel1*8 +: 8];
    assign pal_raddr = nz1 ? n1 : byte1;

    always @(posedge clk) begin
        if (rst || start) begin
            run <= start;
            c <= 10'd0;
            s <= s0;
            noise <= nbase;
        end else if (run) begin
            c <= c + 10'd1;
            s <= s + 16'd1 == stride ? 16'd0 : s + 16'd1;
            noise <= noise + 8'd37;
            if (c + 10'd1 == ncols) run <= 1'b0;
        end
    end

    always @(posedge clk) begin
        v1 <= run && !rst && !start;
        {wr1, nz1, sel1, n1, px1, single1} <= {wr0, nz0, bi[1:0], noise, px0, single};
        {v2, wr2, px2, single2} <= {v1, wr1, px1, single1};
        lb_we_lo <= v2 && wr2 && !(single2 && px2[0]);
        lb_we_hi <= v2 && wr2 && !(single2 && !px2[0]);
        lb_addr <= px2[9:1];
        lb_data <= pal_rdata;
        done <= v2 && !v1;                  // the last column left stage 2
    end
endmodule

`default_nettype wire
