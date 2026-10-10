// The HDMI audio test tone: stereo, 16-bit, -12 dBFS sines, 440 Hz on the left
// and 660 Hz on the right (so the two channels can be told apart).
//
// One sample a `req` (zm_hdmi_tx's aud_req: 48 kHz or 44.1 kHz, from the same
// accumulator as the CTS the sink regenerates the rate from, so the two never
// drift apart).
//
// Each channel is a 32-bit phase accumulator (increment f x 2^32 / fs,
// rounded: the defaults are for 48 kHz) whose top 8 bits index a 256-point sine, kept as a quarter wave of 64
// entries: T[i] = round(8231 x sin(2 pi (i + 0.5) / 256)), 8231 = 32768 x 10^(-12/20).
// The half-step offset makes the quarter wave exactly symmetric. A sample leaves
// the clock after its request; tests/tb/hdmi_audio_tb.cpp computes the same.
`default_nettype none

module hdmi_tone #(
    parameter [31:0] INC_L = 32'd39370534,  // 440 Hz at 48 kHz (42852281 at 44.1)
    parameter [31:0] INC_R = 32'd59055800   // 660 Hz at 48 kHz (64278422 at 44.1)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        req,
    output reg         valid = 1'b0,   // one clock per sample
    output reg  [15:0] left = 16'd0,
    output reg  [15:0] right = 16'd0
);
    localparam [1023:0] QUARTER = {
        256'h20262021201820091FF51FDC1FBE1F9C1F751F481F171EE11EA71E671E231DDB,
        256'h1D8D1D3B1CE51C8A1C2B1BC71B601AF31A831A0F1997191A189A1816178E1703,
        256'h167415E2154C14B31417137812D61231118910DE10310F810ECF0E1A0D640CAB,
        256'h0BF00B340A7609B608F40832076E06A905E3051C0454038B02C201F9012F0065};

    // The 256-point sine at phase p: the quarter wave mirrored and negated.
    function [15:0] sine(input [7:0] p);
        reg [5:0]  i;
        reg [15:0] t;
        begin
            i = p[6] ? ~p[5:0] : p[5:0];
            t = QUARTER[16 * i +: 16];
            sine = p[7] ? 16'd0 - t : t;
        end
    endfunction

    reg [31:0] ph_l = 32'd0, ph_r = 32'd0;
    always @(posedge clk) begin
        if (rst) begin
            {ph_l, ph_r, valid} <= 0;
        end else begin
            valid <= req;
            if (req) begin
                {left, right} <= {sine(ph_l[31:24]), sine(ph_r[31:24])};
                ph_l <= ph_l + INC_L;
                ph_r <= ph_r + INC_R;
            end
        end
    end
endmodule

`default_nettype wire
