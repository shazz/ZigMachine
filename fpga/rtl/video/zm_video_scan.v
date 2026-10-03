// Scanout: reads the display buffers (zm_video_scanfetch.v fills them) in the pixel clock's
// domain, where zm_vtiming points, and drives RGB with DE/HSYNC/VSYNC.
//
// Raster line y lives in buffer y[0]. The scanout fetch publishes a finished line
// (`pub`, with the line number) and the scanout hands the buffer back (`freed`)
// once it has shown that line twice: at the HBL of the next line, or at the VBL
// for line 279. A line is shown only if its buffer holds THAT line; otherwise
// the scanout shows black and `underrun` sticks, so a late compositor is visible
// and never shows another line's pixels.
//
// Outputs are two clocks behind zm_vtiming's (one for the RAM, one registered),
// all of them, so RGB stays aligned with its syncs. Outside the 800x560 raster
// the picture is black: the 20-line bars above and below.
`default_nettype none

module zm_video_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        hsync, vsync, de, zm_active,
    input  wire [9:0]  zm_x,
    input  wire [8:0]  zm_line,
    input  wire        zm_hbl, zm_vbl,
    input  wire [8:0]  zm_hbl_line,
    input  wire [1:0]  pub,                // one clock: buffer b now holds line pub_line[b]
    input  wire [17:0] pub_line,           // {buffer 1's line, buffer 0's line}, stable around pub
    output reg  [1:0]  freed,              // one clock: the scanout is done with buffer b
    output wire [9:0]  dp_raddr,
    input  wire [47:0] dp_rdata,
    output reg  [7:0]  r, g, b,
    output reg         de_o, hs_o, vs_o,
    output reg         underrun = 1'b0
);
    reg [1:0] full = 2'b00;
    reg [8:0] line0, line1;               // the line each buffer holds
    wire       ok = full[zm_line[0]] && (zm_line[0] ? line1 : line0) == zm_line;
    assign dp_raddr = {zm_line[0], zm_x[9:1]};

    always @(posedge clk) begin
        freed <= 2'b00;
        if (rst) {full, underrun} <= 3'b000;
        else begin
            if (zm_hbl && zm_hbl_line != 9'd0) freed[!zm_hbl_line[0]] <= 1'b1;
            if (zm_vbl) freed[1] <= 1'b1;
            full <= (full | pub) & ~freed;
            if (zm_active && !ok) underrun <= 1'b1;
        end
        if (pub[0]) line0 <= pub_line[8:0];
        if (pub[1]) line1 <= pub_line[17:9];
    end

    // Stage 1: the RAM answers; stage 2: the registered outputs.
    reg de1, hs1, vs1, show1, odd1;
    always @(posedge clk) begin
        {de1, hs1, vs1, show1, odd1} <= {de, hsync, vsync, zm_active && ok, zm_x[0]};
        {de_o, hs_o, vs_o} <= {de1, hs1, vs1};
        {b, g, r} <= show1 ? (odd1 ? dp_rdata[47:24] : dp_rdata[23:0]) : 24'd0;
    end
endmodule

`default_nettype wire
