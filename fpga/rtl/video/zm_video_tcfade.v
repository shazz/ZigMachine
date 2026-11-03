// The true-colour fade (HW 1.16.0, machine/video_tc_fade.zig, docs/HW_API.md "True-colour fade"):
// a 565 pixel expanded to 888 by bit replication, faded toward black or white, then offset per
// channel and clamped, in two registered stages (the painter's stage 3 and its output):
//   x  = 888 channel, inverted toward white (255 - x == ~x)
//   p  = x * m + 16, m = 32 - (coef + coef >> 4) latched by the painter   (a DSP48 each)
//   y  = p >> 5, inverted back toward white;  out = clamp(y + ofs, 0, 255)
// coef 0 is m = 32: p >> 5 = x, so the reset registers are the 1.15.0 expansion exactly.
`default_nettype none

module zm_video_tcfade (
    input  wire        clk,
    input  wire [15:0] px,             // the 565 pixel (registered)
    input  wire [5:0]  m,              // 32 - weight, 0..32
    input  wire        white,
    input  wire [23:0] ofs,            // {b, g, r} signed bytes
    output wire [31:0] rgba            // a clock after px: R in the low byte, alpha 255
);
    wire [7:0] r8 = {px[15:11], px[15:13]}, g8 = {px[10:5], px[10:9]}, b8 = {px[4:0], px[4:2]};
    wire [7:0] inv = {8{white}};
    (* use_dsp = "yes" *) reg [13:0] pr, pg, pb;
    reg w1;
    reg [23:0] o1;
    always @(posedge clk) begin
        pr <= (r8 ^ inv) * m + 14'd16;
        pg <= (g8 ^ inv) * m + 14'd16;
        pb <= (b8 ^ inv) * m + 14'd16;
        w1 <= white;
        o1 <= ofs;
    end

    function [7:0] chan(input [13:0] p, input [7:0] o);
        reg [7:0] y;
        reg [9:0] s;                    // y + o, signed: -128 .. 382
        begin
            y = p[12:5] ^ {8{w1}};
            s = {2'b00, y} + {{2{o[7]}}, o};
            chan = s[9] ? 8'd0 : s[8] ? 8'd255 : s[7:0];
        end
    endfunction
    assign rgba = {8'hFF, chan(pb, o1[23:16]), chan(pg, o1[15:8]), chan(pr, o1[7:0])};
endmodule

`default_nettype wire
