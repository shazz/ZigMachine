// The EDID on screen, as hex, for a photo: 50 x 37 cells of 16 x 16 pixels (the
// machine's 8x8 system font, gen/glass_font.vh, drawn 2x) on the 800x600 frame.
//   row  0      EDID  status:S WORD     reads:NN  hpd:H
//   rows 2..17  the base block, 8 bytes a row: "AA: B0  B1 ... B7  =SS"
//   rows 19..34 the extension block, the same way
//   row  36     a legend
// AA is the row's first byte address, SS the row's byte sum mod 256 (from
// edid_reader, so a transcription can be checked a row at a time).
// Three registered stages (EDID/sum RAM, font ROM, pixel): every output, RGB and
// syncs alike, leaves three clocks after its zm_vtiming input. `ch` is the
// character of the pixel leaving, for the testbench.
`default_nettype none

module edid_text (
    input  wire        clk,
    input  wire [10:0] x,              // zm_vtiming's out_x/out_y/de/hsync/vsync
    input  wire [9:0]  y,
    input  wire        de, hs, vs,
    input  wire [2:0]  status,
    input  wire [7:0]  reads,
    input  wire        hpd,
    output wire [7:0]  rd_addr,
    input  wire [7:0]  rd_data,
    output wire [4:0]  sum_addr,
    input  wire [7:0]  sum_data,
    output reg  [7:0]  r = 8'd0,
    output reg  [7:0]  g = 8'd0,
    output reg  [7:0]  b = 8'd0,
    output reg         de_o = 1'b0,
    output reg         hs_o = 1'b0,
    output reg         vs_o = 1'b0,
    output reg  [7:0]  ch = 8'd0
);
    localparam [399:0] HDR = "EDID  status:           reads:    hpd:            ";
    localparam [399:0] LEGEND = "AA: 8 bytes from address AA  =their sum mod 256   ";
    localparam [335:0] WORDS = {"WAIT   ", "OK     ", "NAK A0 ", "NAK OFS", "NAK A1 ", "TIMEOUT"};
    localparam [1:0] K_TEXT = 2'd0, K_ADDR = 2'd1, K_DATA = 2'd2, K_SUM = 2'd3;

    // --- stage 1: which byte and row sum the cell shows
    wire [5:0] row = y[9:4], col = x[9:4];
    wire       blk0 = (row >= 6'd2) && (row < 6'd18), blk1 = (row >= 6'd19) && (row < 6'd35);
    wire [4:0] ri0 = row - 6'd2, ri1 = row - 6'd3;
    wire [4:0] ri = blk0 ? ri0 : ri1;
    wire [3:0] slot = col[5:2] - 4'd1;
    assign rd_addr = {ri, slot[2:0]};
    assign sum_addr = ri;
    reg [5:0] row1 = 6'd0, col1 = 6'd0;
    reg [4:0] ri1_q = 5'd0;
    reg       data1 = 1'b0;
    reg [2:0] gx1 = 3'd0, gy1 = 3'd0, sync1 = 3'd0;
    always @(posedge clk) begin
        {row1, col1, ri1_q, data1} <= {row, col, ri, blk0 || blk1};
        {gx1, gy1, sync1} <= {x[3:1], y[3:1], de, hs, vs};
    end

    function [7:0] hex(input [3:0] v);
        hex = (v < 4'd10) ? 8'h30 + v : 8'h37 + v;
    endfunction
    function [7:0] str(input [399:0] s, input [5:0] c);
        str = (c < 6'd50) ? s[8 * (49 - c) +: 8] : 8'h20;
    endfunction

    // --- stage 2: the character and its kind (colour), then its glyph row
    reg [7:0] c1;
    reg [1:0] k1;
    wire [55:0] word = WORDS[56 * (5 - ((status > 3'd5) ? 3'd5 : status)) +: 56];
    always @(*) begin
        {c1, k1} = {8'h20, K_TEXT};
        if (row1 == 6'd0) begin
            c1 = str(HDR, col1);
            if (col1 == 6'd13) c1 = hex({1'b0, status});
            if (col1 >= 6'd15 && col1 < 6'd22) c1 = word[8 * (21 - col1) +: 8];
            if (col1 == 6'd30) c1 = hex(reads[7:4]);
            if (col1 == 6'd31) c1 = hex(reads[3:0]);
            if (col1 == 6'd38) c1 = hex({3'd0, hpd});
        end else if (row1 == 6'd36) begin
            c1 = str(LEGEND, col1);
        end else if (data1) begin
            case (col1)
                6'd0: {c1, k1} = {hex(ri1_q[4:1]), K_ADDR};
                6'd1: {c1, k1} = {hex({ri1_q[0], 3'd0}), K_ADDR};
                6'd2: {c1, k1} = {8'h3A, K_ADDR};
                6'd36: {c1, k1} = {8'h3D, K_SUM};
                6'd37: {c1, k1} = {hex(sum_data[7:4]), K_SUM};
                6'd38: {c1, k1} = {hex(sum_data[3:0]), K_SUM};
                default:
                    if (col1 >= 6'd4 && col1 < 6'd36 && col1[1:0] == 2'd1) {c1, k1} = {hex(rd_data[7:4]), K_DATA};
                    else if (col1 >= 6'd4 && col1 < 6'd36 && col1[1:0] == 2'd2) {c1, k1} = {hex(rd_data[3:0]), K_DATA};
            endcase
        end
    end

    reg [7:0] font [0:2047];
`include "glass_font.vh"
    reg [7:0] glyph = 8'd0, c2 = 8'd0;
    reg [2:0] gx2 = 3'd0, sync2 = 3'd0;
    reg [1:0] k2 = 2'd0;
    reg       hdr2 = 1'b0;
    always @(posedge clk) begin
        glyph <= font[{c1, gy1}];
        {c2, gx2, sync2, k2, hdr2} <= {c1, gx1, sync1, k1, row1 == 6'd0};
    end

    // --- stage 3: the pixel
    wire [23:0] fg = hdr2 ? 24'hFFFF40 : (k2 == K_ADDR) ? 24'h40E0FF : (k2 == K_SUM) ? 24'h60FF60
                   : (k2 == K_DATA) ? 24'hFFFFFF : 24'hA0A0A0;
    always @(posedge clk) begin
        {r, g, b} <= !sync2[2] ? 24'h000000 : glyph[3'd7 - gx2] ? fg : 24'h000040;
        {de_o, hs_o, vs_o, ch} <= {sync2, sync2[2] ? c2 : 8'h00};
    end
endmodule

`default_nettype wire
