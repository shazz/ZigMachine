// The video pipeline end to end: the compositor and its plane mixer in the
// compositor's clock (`clk`, the SoC's system clock on the board), the timing
// and the scanout in the pixel clock (`pix_clk`, 40 MHz), the display buffers
// between them. Ports are zm_video_comp's, plus the picture and the HBL/VBL
// strobes brought into `clk`'s domain for the CPU.
//
// The compositor may run any number of lines ahead; it stalls by itself when
// both display buffers hold lines not yet shown (`dp_free`), so whoever issues
// the passes only has to issue them in order. A compositor clock of at least
// twice the pixel clock is the design point (fpga/rtl/video/README.md).
`default_nettype none

module zm_video_out (
    input  wire        clk,
    input  wire        rst,
    input  wire        pix_clk,
    input  wire        pix_rst,
    input  wire        cpu_we,
    input  wire [20:0] cpu_waddr,
    input  wire [3:0]  cpu_be,
    input  wire [31:0] cpu_wdata,
    input  wire [4:0]  cpu_rword,
    output wire [31:0] cpu_rdata,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [1:0]  cmd_op,
    input  wire [1:0]  cmd_plane,
    input  wire [8:0]  cmd_line,
    input  wire        cmd_mix,
    input  wire        cmd_last,
    output wire        pass_done,
    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire [31:0] mem_req_addr,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_data,
    input  wire [8:0]  lb_raddr,
    output wire [63:0] lb_rdata,
    output wire        overflow,
    output wire        line_ready,
    output wire [8:0]  ready_line,
    output wire        mix_busy,
    output wire        mix_hazard,
    // the picture, in pix_clk's domain
    output wire [7:0]  r, g, b,
    output wire        de, hsync, vsync,
    output wire        underrun,
    // in clk's domain: a raster line is about to be shown / the raster is done
    output wire        hbl,
    output reg  [8:0]  hbl_line,
    output wire        vbl
);
    wire t_hs, t_vs, t_de, t_active, t_hbl, t_vbl;
    wire [9:0] t_x;
    wire [8:0] t_line, t_hbl_line;
    zm_vtiming u_timing (
        .clk(pix_clk), .rst(pix_rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .out_x(), .out_y(),
        .zm_active(t_active), .zm_x(t_x), .zm_line(t_line), .zm_hbl(t_hbl), .zm_hbl_line(t_hbl_line),
        .zm_vbl(t_vbl));

    // Publication (clk -> pix_clk) and release (pix_clk -> clk) of each display buffer.
    wire [1:0] pub_c = {line_ready && ready_line[0], line_ready && !ready_line[0]};
    wire [1:0] pub_p, freed_p, freed_c;
    reg [17:0] pub_line;
    reg [1:0] dp_free = 2'b11;
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

    // The HBL line number is held for a whole raster line, so it is sampled on the pulse.
    reg [8:0] hbl_line_p;
    always @(posedge pix_clk) if (t_hbl) hbl_line_p <= t_hbl_line;
    zm_video_sync u_hbl (.src_clk(pix_clk), .src_pulse(t_hbl), .dst_clk(clk), .dst_pulse(hbl));
    zm_video_sync u_vbl (.src_clk(pix_clk), .src_pulse(t_vbl), .dst_clk(clk), .dst_pulse(vbl));
    always @(posedge clk) if (hbl) hbl_line <= hbl_line_p;

    wire [9:0] dp_raddr;
    wire [47:0] dp_rdata;
    zm_video_comp u_comp (
        .clk(clk), .rst(rst), .cpu_we(cpu_we), .cpu_waddr(cpu_waddr), .cpu_be(cpu_be),
        .cpu_wdata(cpu_wdata), .cpu_rword(cpu_rword), .cpu_rdata(cpu_rdata), .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready), .cmd_op(cmd_op), .cmd_plane(cmd_plane), .cmd_line(cmd_line),
        .cmd_mix(cmd_mix), .cmd_last(cmd_last), .pass_done(pass_done), .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready), .mem_req_addr(mem_req_addr), .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_data(mem_rsp_data), .lb_raddr(lb_raddr), .lb_rdata(lb_rdata), .overflow(overflow),
        .dp_clk(pix_clk), .dp_raddr(dp_raddr), .dp_rdata(dp_rdata), .dp_free(dp_free),
        .line_ready(line_ready), .ready_line(ready_line), .mix_busy(mix_busy), .mix_hazard(mix_hazard));

    zm_video_scan u_scan (
        .clk(pix_clk), .rst(pix_rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .zm_active(t_active),
        .zm_x(t_x), .zm_line(t_line), .zm_hbl(t_hbl), .zm_vbl(t_vbl), .zm_hbl_line(t_hbl_line),
        .pub(pub_p), .pub_line(pub_line), .freed(freed_p), .dp_raddr(dp_raddr), .dp_rdata(dp_rdata),
        .r(r), .g(g), .b(b), .de_o(de), .hs_o(hsync), .vs_o(vsync), .underrun(underrun));
endmodule

`default_nettype wire
