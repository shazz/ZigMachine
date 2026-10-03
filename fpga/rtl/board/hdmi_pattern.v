// The HDMI bring-up test pattern (rtl/board/hdmi_test_top.v), on the machine's
// own VESA 800x600@60 timing (rtl/video/zm_vtiming.v). One look proves the path:
//   y   0..299  seven 75 % colour bars (white, yellow, cyan, green, magenta, red, blue)
//   y 300..339  the SMPTE castellations under them (blue, black, magenta, black, cyan, black, white)
//   y 340..459  a dark band with a 48x48 orange box bouncing in it, one step a frame
//   y 460..599  four 35-line ramps (red, green, blue, grey): level n at x = 16 + 3n,
//               every 8-bit level exactly 3 pixels wide, black margins either side
// and on top of all of it a 1-pixel white frame on the exact edges (x 0 and 799,
// y 0 and 599) with a 1-pixel black ring inside it, so a cropped or shifted edge
// shows. Everything is registered once: rgb, de and the syncs leave together,
// one clock after zm_vtiming's outputs.
`default_nettype none

module hdmi_pattern (
    input  wire       clk,            // pixel clock, 40 MHz
    input  wire       rst,
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b,
    output reg        de,
    output reg        hsync,
    output reg        vsync
);
    localparam [7:0] BAR = 8'd191;           // 75 %
    localparam [7:0] BAND = 8'd32;
    localparam integer BAND_Y = 340, BAND_H = 120, BOX = 48;
    localparam integer BOX_X_MIN = 2, BOX_X_MAX = 798 - BOX, BOX_Y_MAX = BAND_H - BOX;
    localparam integer RAMP_X = 16, RAMP_Y = 460, RAMP_H = 35;

    wire        t_hs, t_vs, t_de;
    wire [10:0] out_x;
    wire [9:0]  out_y;
    zm_vtiming u_t (.clk(clk), .rst(rst), .hsync(t_hs), .vsync(t_vs), .de(t_de), .out_x(out_x), .out_y(out_y),
                    .zm_active(), .zm_x(), .zm_line(), .zm_hbl(), .zm_hbl_line(), .zm_vbl());
    wire [9:0] x = out_x[9:0];
    wire [9:0] y = out_y;

    // The box moves once a frame, at the first clock of vertical blanking.
    reg [9:0] bx;
    reg [6:0] by;
    reg       right, down;
    wire      frame = (out_x == 11'd0) && (out_y == 10'd600);
    always @(posedge clk) begin
        if (rst) begin
            {bx, by, right, down} <= {10'd100, 7'd10, 1'b1, 1'b1};
        end else if (frame) begin
            if (right) begin
                if (bx + 10'd4 > BOX_X_MAX) right <= 1'b0; else bx <= bx + 10'd4;
            end else begin
                if (bx < BOX_X_MIN + 4) right <= 1'b1; else bx <= bx - 10'd4;
            end
            if (down) begin
                if (by + 7'd2 > BOX_Y_MAX) down <= 1'b0; else by <= by + 7'd2;
            end else begin
                if (by < 7'd2) down <= 1'b1; else by <= by - 7'd2;
            end
        end
    end

    // Which of the seven bars x is in (six of 114 pixels, the last 116).
    wire [2:0] bar = (x < 114) ? 3'd0 : (x < 228) ? 3'd1 : (x < 342) ? 3'd2 : (x < 456) ? 3'd3
                   : (x < 570) ? 3'd4 : (x < 684) ? 3'd5 : 3'd6;
    reg [2:0] bar_rgb, cast_rgb;  // {r, g, b} on/off
    always @(*) begin
        case (bar)
            3'd0: {bar_rgb, cast_rgb} = {3'b111, 3'b001};
            3'd1: {bar_rgb, cast_rgb} = {3'b110, 3'b000};
            3'd2: {bar_rgb, cast_rgb} = {3'b011, 3'b101};
            3'd3: {bar_rgb, cast_rgb} = {3'b010, 3'b000};
            3'd4: {bar_rgb, cast_rgb} = {3'b101, 3'b011};
            3'd5: {bar_rgb, cast_rgb} = {3'b100, 3'b000};
            default: {bar_rgb, cast_rgb} = {3'b001, 3'b111};
        endcase
    end

    // The ramps: (x - 16) / 3 as a multiply-shift (exact for 0..767).
    wire [9:0]  rx = x - RAMP_X[9:0];
    wire [20:0] rx_mul = rx * 11'd683;
    wire [7:0]  level = rx_mul[18:11];
    wire        in_ramp_x = (x >= RAMP_X) && (x < RAMP_X + 768);
    wire [9:0]  ry = y - RAMP_Y[9:0];
    wire [1:0]  ramp = (ry < RAMP_H) ? 2'd0 : (ry < 2 * RAMP_H) ? 2'd1 : (ry < 3 * RAMP_H) ? 2'd2 : 2'd3;

    wire [9:0] band_y = y - BAND_Y[9:0];
    wire in_box = (x >= bx) && (x < bx + BOX) && (band_y >= {3'd0, by}) && (band_y < {3'd0, by} + BOX);
    wire edge0 = (x == 10'd0) || (x == 10'd799) || (y == 10'd0) || (y == 10'd599);
    wire edge1 = (x == 10'd1) || (x == 10'd798) || (y == 10'd1) || (y == 10'd598);

    reg [23:0] rgb;
    always @(*) begin
        if (edge0) rgb = 24'hFFFFFF;
        else if (edge1) rgb = 24'h000000;
        else if (y < 300) rgb = {{8{bar_rgb[2]}} & BAR, {8{bar_rgb[1]}} & BAR, {8{bar_rgb[0]}} & BAR};
        else if (y < BAND_Y) rgb = {{8{cast_rgb[2]}} & BAR, {8{cast_rgb[1]}} & BAR, {8{cast_rgb[0]}} & BAR};
        else if (y < RAMP_Y) rgb = in_box ? 24'hFF8000 : {3{BAND}};
        else if (!in_ramp_x) rgb = 24'h000000;
        else case (ramp)
            2'd0: rgb = {level, 16'h0000};
            2'd1: rgb = {8'h00, level, 8'h00};
            2'd2: rgb = {16'h0000, level};
            default: rgb = {3{level}};
        endcase
    end

    always @(posedge clk) begin
        {r, g, b} <= t_de ? rgb : 24'h000000;
        {de, hsync, vsync} <= rst ? 3'b000 : {t_de, t_hs, t_vs};
    end
endmodule

`default_nettype wire
