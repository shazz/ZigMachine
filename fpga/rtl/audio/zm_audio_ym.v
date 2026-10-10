// The YM2149: jotego's jt49 (GPL-3, third_party/jt49, used unmodified as a
// separate module) clocked as the ST's PSG, plus the box filter that turns its
// output into one value a sample.
//   - `ym_cen` is the chip's 2 MHz master clock as an enable (SEL high: no extra
//     divide), so a tone of period P is 2 MHz / (16 P), as on the ST;
//   - MUTE_NULL_PERIOD 0: a period of 0 behaves as 1 (the real chip, and
//     machine/audio/ym.zig), not as silence;
//   - jt49's `sound` (A + B + C through its 32-step DAC, 0..765) is summed on
//     every YM clock and the sum handed out on `strobe` with the count of YM
//     clocks in it (45 or 46 at 44.1 kHz): the mean over the sample period, a
//     box filter. It is what ym.zig approximates with its 0.5 gate for tones
//     above Nyquist; zm_audio_mix divides by the count.
// A register write is one clock of `wr`; writes must be at least two clocks
// apart, so that each one is an edge for jt49 (it retriggers the envelope on the
// edge of an R13 write). zm_audio_core's `ready` spaces them.
`default_nettype none

module zm_audio_ym (
    input  wire        clk,
    input  wire        rst,
    input  wire        ym_cen,         // 2 MHz
    input  wire        wr,
    input  wire [3:0]  addr,
    input  wire [7:0]  din,
    input  wire        strobe,         // close the sample period
    output reg  [15:0] sum = 16'd0,    // valid from the clock after `strobe`
    output reg  [6:0]  cnt = 7'd0
);
    wire [9:0] sound;
    jt49 #(.MUTE_NULL_PERIOD(0)) u_psg (
        .rst_n(!rst), .clk(clk), .clk_en(ym_cen), .addr(addr), .cs_n(!wr), .wr_n(!wr), .din(din),
        .sel(1'b1), .dout(), .sound(sound), .A(), .B(), .C(), .sample(),
        .IOA_in(8'd0), .IOA_out(), .IOA_oe(), .IOB_in(8'd0), .IOB_out(), .IOB_oe());

    reg  [15:0] acc = 16'd0;
    reg  [6:0]  n = 7'd0;
    wire [15:0] acc_in = ym_cen ? acc + {6'd0, sound} : acc;
    wire [6:0]  n_in = ym_cen ? n + 7'd1 : n;

    always @(posedge clk) begin
        if (rst) begin
            {acc, n, sum, cnt} <= 0;
        end else if (strobe) begin
            {sum, cnt} <= {acc_in, n_in};
            {acc, n} <= 0;
        end else begin
            {acc, n} <= {acc_in, n_in};
        end
    end
endmodule

`default_nettype wire
