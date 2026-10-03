// Plane mixer: what the browser shows, built from the compositor's line buffer.
//
// The browser stacks one canvas per enabled plane (docs/sealed-loader.js);
// canvas k holds the PFB as it is after plane k's pass, and Chrome draws them
// bottom first, source-over, onto the tube's #121010. In premultiplied 8-bit
// arithmetic, exactly as Skia does it (tools/video_dump/vmix.c is the oracle):
//     P = round(c * a / 255)            putImageData premultiplies
//     D = P + (D * (256 - a) >> 8)      each canvas drawn over the last
// So after a plane's pass over a line, one SWEEP folds the line buffer into the
// accumulator line: D = over(L, D), D starting from the tube on the line's
// first sweep of the frame (`first`). The compositor fills the accumulator
// from the frame buffer's picture row before the sweep, and writes it back
// after (zm_video_rowio.v); between sweeps it is the picture's row y.
//
// A sweep reads one pair (two pixels) a clock, 400 clocks, from pair 0 up. The
// accumulator's other ports (`ld_*` writes, `st_*` reads) belong to the row
// I/O while no sweep runs.
`default_nettype none

module zm_video_mix #(
    parameter [23:0] TUBE = 24'h101012     // #121010 (docs/css/crt.css), {B, G, R}
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,              // one clock: sweep the line buffer
    input  wire        first,              // over the tube, not the accumulator
    output wire        busy,
    output reg         done,               // one clock: the sweep's last write landed
    output wire [8:0]  lb_raddr,
    input  wire [63:0] lb_rdata,           // the clock after lb_raddr
    // the accumulator, pair -> {pixel 2x+1 BGR, pixel 2x BGR}, for the row I/O
    input  wire        ld_we,
    input  wire [8:0]  ld_addr,
    input  wire [47:0] ld_data,
    input  wire [8:0]  st_raddr,
    output wire [47:0] st_rdata            // the clock after st_raddr
);
`include "zm_video_memmap.vh"

    localparam integer PAIRS = ZM_RASTER_WIDTH / 2;
    reg        run = 1'b0;
    reg [8:0]  m;
    reg        f_r;
    // Pipeline: 1 = L and accumulator data, 2 = products, 3 = result written.
    reg        v1, v2, v3;
    reg [8:0]  m1, m2, m3;
    assign lb_raddr = m;
    assign busy = run || v1 || v2 || v3;

    always @(posedge clk) begin
        if (rst) run <= 1'b0;
        else if (start) {run, m, f_r} <= {1'b1, 9'd0, first};
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
    zm_video_sdpram #(.AW(9), .DW(48)) u_acc (.clk(clk), .we({6{v3 || ld_we}}), .waddr(v3 ? m3 : ld_addr),
        .wdata(v3 ? mixed : ld_data), .raddr(run ? m : st_raddr), .rdata(acc_rdata));
    assign st_rdata = acc_rdata;
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
endmodule

`default_nettype wire
