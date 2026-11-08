// Scanout: reads the display buffers (zm_video_scanfetch.v fills them) in the pixel clock's
// domain, where zm_vtiming points, and drives RGB with DE/HSYNC/VSYNC.
//
// Raster line y lives in buffer y[0]. The scanout fetch publishes a finished line
// (`pub`, with the line number) and the scanout hands the buffer back (`freed`)
// once it has shown that line: at the HBL of the next line, or at the VBL for
// the last one (279, or the desk's 479: both odd, so both in buffer 1). A line is
// shown only if its buffer holds THAT line; otherwise the scanout shows black and
// `underrun` sticks, so a late fetch is visible and never shows another line's pixels.
//
// A buffer word is one 64-bit beat. Normal mode: {pixel 2x+1, pixel 2x} as
// {0, B, G, R} words, 400 a line. Desk mode (`desk`, HW 1.17.0): eight palette
// indices, byte 0 leftmost, 80 a line, looked up in the mirror of palette 0
// (`pal_*`, zm_video_desk.v) one clock later.
//
// Outputs are three clocks behind zm_vtiming's in BOTH modes (the RAM, the
// mirror's read in desk mode or a register in normal mode, the output
// register), so RGB stays aligned with its syncs. Outside the raster the
// picture is black: the bars.
`default_nettype none

module zm_video_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        hsync, vsync, de, zm_active, desk,
    input  wire [9:0]  zm_x,
    input  wire [8:0]  zm_line,
    input  wire        zm_hbl, zm_vbl,
    input  wire [8:0]  zm_hbl_line,
    input  wire [1:0]  pub,                // one clock: buffer b now holds line pub_line[b]
    input  wire [17:0] pub_line,           // {buffer 1's line, buffer 0's line}, stable around pub
    output reg  [1:0]  freed,              // one clock: the scanout is done with buffer b
    output wire [9:0]  dp_raddr,
    input  wire [63:0] dp_rdata,
    output wire [7:0]  pal_raddr,          // desk: the mirror of palette 0
    input  wire [23:0] pal_rdata,          //   {B, G, R}, the clock after its address
    output reg  [7:0]  r, g, b,
    output reg         de_o, hs_o, vs_o,
    output reg         underrun = 1'b0
);
    reg [1:0] full = 2'b00;
    reg [8:0] line0, line1;               // the line each buffer holds
    wire       ok = full[zm_line[0]] && (zm_line[0] ? line1 : line0) == zm_line;
    wire [8:0] word = desk ? {2'b00, zm_x[9:3]} : zm_x[9:1];
    assign dp_raddr = {zm_line[0], word};

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

    // Stage 1: the RAM answers (desk: its byte addresses the mirror); stage 2: the mirror answers,
    // or the normal pixel is registered; stage 3: the registered outputs.
    reg de1, hs1, vs1, show1, desk1, odd1, de2, hs2, vs2, dshow2;
    reg [2:0] byte1;
    reg [23:0] rgb2;
    assign pal_raddr = dp_rdata[{byte1, 3'b000} +: 8];
    always @(posedge clk) begin
        {de1, hs1, vs1, show1, odd1} <= {de, hsync, vsync, zm_active && ok, zm_x[0]};
        {desk1, byte1} <= {desk, zm_x[2:0]};
        {de2, hs2, vs2, dshow2} <= {de1, hs1, vs1, show1 && desk1};
        rgb2 <= show1 && !desk1 ? (odd1 ? dp_rdata[55:32] : dp_rdata[23:0]) : 24'd0;
        {de_o, hs_o, vs_o} <= {de2, hs2, vs2};
        {b, g, r} <= dshow2 ? pal_rdata : rgb2;
    end
endmodule

`default_nettype wire
