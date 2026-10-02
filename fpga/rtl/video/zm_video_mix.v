// Plane mixer: what the browser shows, built from the compositor's line buffer.
//
// The browser stacks one canvas per enabled plane (docs/sealed-loader.js);
// canvas k holds the PFB as it is after plane k's pass, and Chrome draws them
// bottom first, source-over, onto the tube's #121010. In premultiplied 8-bit
// arithmetic, exactly as Skia does it (tools/video_dump/vmix.c is the oracle):
//     P = round(c * a / 255)            putImageData premultiplies
//     D = P + (D * (256 - a) >> 8)      each canvas drawn over the last
// So after every plane pass, one SWEEP folds the line buffer into an
// accumulator line: D = over(L, D), D starting from the tube on the first sweep
// of a line. The last sweep of a line writes the display buffer instead, which
// the scanout reads in its own clock domain: one 800-pixel RGB line per buffer,
// two buffers (ping-pong by raster line parity).
//
// A sweep reads one pair (two pixels) a clock, 400 clocks, from pair 0 up. The
// compositor starts it the clock after the pass that filled L, and no writer of
// L can start before the clock after that and writes at most a pair a clock,
// also from low pairs up, so the sweep always reads a pair before it is
// rewritten (zm_video_comp checks this as `mix_hazard`).
`default_nettype none

module zm_video_mix #(
    parameter [23:0] TUBE = 24'h101012     // #121010 (docs/css/crt.css), {B, G, R}
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,              // one clock: sweep the line buffer
    input  wire        first,              // over the tube, not the accumulator
    input  wire        last,               // into display buffer `dbuf`
    input  wire        dbuf,
    output wire        busy,
    output wire [8:0]  rd_ptr,             // the next pair the sweep reads
    output reg         done,               // one clock: the sweep's last write landed
    output wire [8:0]  lb_raddr,
    input  wire [63:0] lb_rdata,           // the clock after lb_raddr
    // the display buffers: {buffer, pair} -> 2 x RGB, read in the scanout's clock
    input  wire        dp_clk,
    input  wire [9:0]  dp_raddr,
    output wire [47:0] dp_rdata
);
`include "zm_video_memmap.vh"

    localparam integer PAIRS = ZM_RASTER_WIDTH / 2;
    reg        run = 1'b0;
    reg [8:0]  m;
    reg        f_r, l_r, b_r;
    // Pipeline: 1 = L and accumulator data, 2 = products, 3 = result written.
    reg        v1, v2, v3;
    reg [8:0]  m1, m2, m3;
    assign lb_raddr = m;
    assign rd_ptr = m;
    assign busy = run || v1 || v2 || v3;

    always @(posedge clk) begin
        if (rst) run <= 1'b0;
        else if (start) {run, m, f_r, l_r, b_r} <= {1'b1, 9'd0, first, last, dbuf};
        else if (run) begin
            m <= m + 9'd1;
            if (m == PAIRS - 1) run <= 1'b0;
        end
        {v1, m1} <= {run && !rst, m};
        {v2, m2} <= {v1 && !rst, m1};
        {v3, m3} <= {v2 && !rst, m2};
        done <= v3 && !v2 && !rst;
    end

    // The accumulator line: D between the sweeps of one line.
    wire [47:0] acc_rdata, mixed;
    zm_video_sdpram #(.AW(9), .DW(48)) u_acc (.clk(clk), .we({6{v3}}), .waddr(m3), .wdata(mixed),
        .raddr(m), .rdata(acc_rdata));
    wire [47:0] dst = f_r ? {TUBE, TUBE} : acc_rdata;

    // Six channels: 2 pixels x {R, G, B}. Stage 2 registers the products.
    genvar i;
    generate
        for (i = 0; i < 6; i = i + 1) begin : ch
            wire [7:0] a = lb_rdata[(i / 3) * 32 + 24 +: 8];
            wire [7:0] c = lb_rdata[(i / 3) * 32 + (i % 3) * 8 +: 8];
            wire [7:0] d = dst[i * 8 +: 8];
            reg [15:0] pm;
            reg [16:0] ov;
            always @(posedge clk) begin
                pm <= c * a;
                ov <= d * (9'd256 - {1'b0, a});
            end
            // round(pm / 255), exact for pm <= 255 * 255
            wire [16:0] r = {1'b0, pm} + 17'd128;
            wire [16:0] p = (r + (r >> 8)) >> 8;
            reg [7:0] o;
            always @(posedge clk) o <= p[7:0] + ov[15:8];
            assign mixed[i * 8 +: 8] = o;
        end
    endgenerate

    zm_video_dcram #(.AW(10), .DW(48)) u_disp (.wclk(clk), .we(v3 && l_r), .waddr({b_r, m3}),
        .wdata(mixed), .rclk(dp_clk), .raddr(dp_raddr), .rdata(dp_rdata));
endmodule

`default_nettype wire
