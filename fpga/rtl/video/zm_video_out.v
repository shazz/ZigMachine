// The video pipeline end to end. In `clk` (the SoC's system clock): the
// compositor, which builds each frame into a picture in memory at its own
// speed, and the scanout fetch, which reads the shown picture back a line ahead
// of the beam. In `pix_clk` (40 MHz): zm_vtiming and the scanout. The display
// line buffers cross between them.
//
// Two pictures, double-buffered (`fb0_base`, `fb1_base`): the compositor writes
// the back one while the scanout shows the front one. PRESENT marks the back
// one complete; the swap happens at the next VBL, and until then a pass that
// would write a picture is not taken (`d_ok`), so the shown picture is never
// written and a frame on the screen is always one whole picture, one frame late.
// The compositor has no deadline; only the scanout fetch has one (a raster
// line, 2,112 pixel clocks), and `underrun` sticks if it ever misses it.
`default_nettype none

module zm_video_out (
    input  wire        clk,
    input  wire        rst,
    input  wire        pix_clk,
    input  wire        pix_rst,
    input  wire [31:0] vbase,
    input  wire [31:0] fb0_base,
    input  wire [31:0] fb1_base,
    input  wire        cpu_we,
    input  wire [20:0] cpu_waddr,
    input  wire [3:0]  cpu_be,
    input  wire [31:0] cpu_wdata,
    input  wire [2:0]  cpu_sel,
    input  wire [4:0]  cpu_rword,
    output wire [31:0] cpu_rdata,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [2:0]  cmd_op,
    input  wire [1:0]  cmd_plane,
    input  wire [8:0]  cmd_line,
    input  wire        cmd_mix,
    input  wire        cmd_first,
    output wire        painted,
    output wire        pass_done,
    // the compositor's memory ports (zm_video_comp.v) ...
    output wire        rd_req_valid,
    input  wire        rd_req_ready,
    output wire [31:0] rd_req_addr,
    output wire [9:0]  rd_req_len,
    input  wire        rd_rsp_valid,
    input  wire [63:0] rd_rsp_data,
    output wire        wr_req_valid,
    input  wire        wr_req_ready,
    output wire [31:0] wr_req_addr,
    output wire [9:0]  wr_req_len,
    output wire        wr_dat_valid,
    input  wire        wr_dat_ready,
    output wire [63:0] wr_dat,
    input  wire        wr_busy,
    // ... and the scanout fetch's read port
    output wire        sc_req_valid,
    input  wire        sc_req_ready,
    output wire [31:0] sc_req_addr,
    output wire [9:0]  sc_req_len,
    input  wire        sc_rsp_valid,
    input  wire [63:0] sc_rsp_data,
    output wire        overflow,
    // the picture, in pix_clk's domain
    output wire [7:0]  r, g, b,
    output wire        de, hsync, vsync,
    output wire        underrun,
    // in clk's domain
    output wire        vbl,              // one clock: the raster is done
    output reg         front = 1'b0,     // the picture being shown
    output reg         pending = 1'b0,   // the back picture is complete, waiting for the VBL
    output reg  [31:0] swaps = 32'd0     // pictures shown so far
);
    wire t_hs, t_vs, t_de, t_active, t_hbl, t_vbl;
    wire [9:0] t_x;
    wire [8:0] t_line, t_hbl_line;
    zm_vtiming u_timing (
        .clk(pix_clk), .rst(pix_rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .out_x(), .out_y(),
        .zm_active(t_active), .zm_x(t_x), .zm_line(t_line), .zm_hbl(t_hbl), .zm_hbl_line(t_hbl_line),
        .zm_vbl(t_vbl));
    zm_video_sync u_vbl (.src_clk(pix_clk), .src_pulse(t_vbl), .dst_clk(clk), .dst_pulse(vbl));

    // --- the two pictures: PRESENT makes the back one pending, the VBL swaps ---
    wire present, swap = pending && vbl;
    wire front_n = front ^ swap;           // the picture shown from this VBL on
    always @(posedge clk) begin
        if (rst) {front, pending, swaps} <= {1'b0, 1'b0, 32'd0};
        else begin
            front <= front_n;
            pending <= (pending && !vbl) || present;
            if (swap) swaps <= swaps + 32'd1;
        end
    end

    zm_video_comp u_comp (
        .clk(clk), .rst(rst), .vbase(vbase), .dbase(front ? fb0_base : fb1_base), .d_ok(!pending),
        .cpu_we(cpu_we), .cpu_waddr(cpu_waddr), .cpu_be(cpu_be), .cpu_wdata(cpu_wdata), .cpu_sel(cpu_sel),
        .cpu_rword(cpu_rword),
        .cpu_rdata(cpu_rdata), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_op(cmd_op),
        .cmd_plane(cmd_plane), .cmd_line(cmd_line), .cmd_mix(cmd_mix), .cmd_first(cmd_first),
        .painted(painted), .pass_done(pass_done), .present(present),
        .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready), .rd_req_addr(rd_req_addr),
        .rd_req_len(rd_req_len), .rd_rsp_valid(rd_rsp_valid), .rd_rsp_data(rd_rsp_data),
        .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready), .wr_req_addr(wr_req_addr),
        .wr_req_len(wr_req_len), .wr_dat_valid(wr_dat_valid), .wr_dat_ready(wr_dat_ready), .wr_dat(wr_dat),
        .wr_busy(wr_busy), .overflow(overflow));

    // --- scanout fetch -> display buffers -> scanout, with their hand-over ---
    wire line_ready, dp_we;
    wire [8:0] ready_line;
    wire [9:0] dp_waddr, dp_raddr;
    wire [47:0] dp_wdata, dp_rdata;
    reg [1:0] dp_free = 2'b11;
    zm_video_scanfetch u_fetch (
        .clk(clk), .rst(rst), .vbl(vbl), .base(front_n ? fb1_base : fb0_base), .dp_free(dp_free),
        .rd_req_valid(sc_req_valid), .rd_req_ready(sc_req_ready), .rd_req_addr(sc_req_addr),
        .rd_req_len(sc_req_len), .rd_rsp_valid(sc_rsp_valid), .rd_rsp_data(sc_rsp_data), .dp_we(dp_we),
        .dp_waddr(dp_waddr), .dp_wdata(dp_wdata), .line_ready(line_ready), .ready_line(ready_line));
    zm_video_dcram #(.AW(10), .DW(48)) u_disp (.wclk(clk), .we(dp_we), .waddr(dp_waddr), .wdata(dp_wdata),
        .rclk(pix_clk), .raddr(dp_raddr), .rdata(dp_rdata));

    // Publication (clk -> pix_clk) and release (pix_clk -> clk) of each display buffer.
    wire [1:0] pub_c = {line_ready && ready_line[0], line_ready && !ready_line[0]};
    wire [1:0] pub_p, freed_p, freed_c;
    reg [17:0] pub_line;
    always @(posedge clk) begin
        if (pub_c[0]) pub_line[8:0] <= ready_line;
        if (pub_c[1]) pub_line[17:9] <= ready_line;
        if (rst) dp_free <= 2'b11;
        else dp_free <= (dp_free | freed_c) & ~pub_c;
    end
    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : buf_sync
            zm_video_sync u_pub (.src_clk(clk), .src_pulse(pub_c[i]), .dst_clk(pix_clk), .dst_pulse(pub_p[i]));
            zm_video_sync u_free (.src_clk(pix_clk), .src_pulse(freed_p[i]), .dst_clk(clk), .dst_pulse(freed_c[i]));
        end
    endgenerate

    zm_video_scan u_scan (
        .clk(pix_clk), .rst(pix_rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .zm_active(t_active),
        .zm_x(t_x), .zm_line(t_line), .zm_hbl(t_hbl), .zm_vbl(t_vbl), .zm_hbl_line(t_hbl_line),
        .pub(pub_p), .pub_line(pub_line), .freed(freed_p), .dp_raddr(dp_raddr), .dp_rdata(dp_rdata),
        .r(r), .g(g), .b(b), .de_o(de), .hs_o(hsync), .vs_o(vsync), .underrun(underrun));
endmodule

`default_nettype wire
