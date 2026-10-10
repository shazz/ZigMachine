// The machine's mix (machine/audio/engine.zig + ym.zig), on the units of
// zm_audio_pcm (2^-23 of full scale):
//   bus = Paula channels + YM; clamped to [-1, 1]; 16-bit = floor(bus x 32768),
//   +1.0 saturating to 32767.
// The YM term is ym.zig's `mix x 0.33` with jt49's DAC in place of ym.zig's
// table: each channel at most 0.33 of full scale, positive only (as on the ST
// and in the machine, a DC offset). With jt49's sum over the sample period
// `ym_sum` (0..765 a YM clock) and its YM clock count `ym_cnt`:
//   ym = ym_sum / ym_cnt x 0.33 / 255 = (ym_sum x K[ym_cnt]) >> 8,
//   K[c] = round(0.33 x 2^31 / (255 c)), tabled for c = 40..47 (48 kHz takes 41
// or 42 YM clocks a sample, 44.1 kHz 45 or 46); any other count mixes no YM
// and pulses `bad_cnt`.
// Two clocks from `start` to `valid`, one multiplier.
`default_nettype none

module zm_audio_mix (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [27:0] pcm_l,
    input  wire signed [27:0] pcm_r,
    input  wire [15:0]        ym_sum,
    input  wire [6:0]         ym_cnt,
    output reg                valid = 1'b0,
    output reg  [15:0]        out_l = 16'd0,
    output reg  [15:0]        out_r = 16'd0,
    output reg                bad_cnt = 1'b0
);
    reg [16:0] k;
    always @(*) begin
        case (ym_cnt)
            7'd40: k = 17'd69477;  7'd41: k = 17'd67783;  7'd42: k = 17'd66169;  7'd43: k = 17'd64630;
            7'd44: k = 17'd63161;  7'd45: k = 17'd61758;  7'd46: k = 17'd60415;  7'd47: k = 17'd59130;
            default: k = 17'd0;
        endcase
    end

    // The 2^-23 bus, clamped, to 16 bits: an arithmetic shift is the floor.
    function [15:0] to16(input signed [28:0] bus);
        reg signed [28:0] c;
        begin
            c = (bus > 29'sd8388608) ? 29'sd8388608 : (bus < -29'sd8388608) ? -29'sd8388608 : bus;
            to16 = (c == 29'sd8388608) ? 16'h7FFF : c[23:8];
        end
    endfunction

    reg  [32:0] ym_p = 33'd0;
    reg         stage = 1'b0;
    wire signed [28:0] ym = $signed({4'd0, ym_p[32:8]});
    always @(posedge clk) begin
        if (rst) begin
            {valid, stage, bad_cnt} <= 0;
        end else begin
            stage <= start;
            bad_cnt <= start && k == 17'd0 && ym_cnt != 7'd0;
            valid <= stage;
            if (start) begin
                ym_p <= ym_sum * k;
            end
            if (stage) begin
                out_l <= to16(pcm_l + ym);
                out_r <= to16(pcm_r + ym);
            end
        end
    end
endmodule

`default_nettype wire
