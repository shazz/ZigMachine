// The POKEY in the audio core: zm_pokey (the cycle-exact chip, held to
// machine/audio/pokey.zig) run in step with the samples, so the core's sound is
// the machine's sample for sample:
//   - each sample takes the machine cycles machine/audio/pokey.zig's sample()
//     takes: the clock's Hz / 44100 as an exact fraction (NTSC 3125/77 = 40.58,
//     PAL 180200000/4481001 = 40.21), so 40 or 41 a sample, from an accumulator
//     that a POKEY_CLOCK write resets (as machinePokeyClock resets the model's);
//   - on `strobe` it runs them in a burst, one a clock, and sums `mix` (0..60)
//     after each, as the model does; `busy` is high until `sum` and `cnt` hold
//     the sample (zm_audio_core holds the mix and the writes back until then);
//   - so a write that landed before the strobe is in every cycle of the sample,
//     exactly as the model applies it between two samples; a write that comes
//     during a burst is held (one deep) and lands after it;
//   - `silence` (machineAudioReset) writes the four AUDC registers to 0 over
//     four clocks, as machine/machine_audio.zig zeroes the four volumes.
`default_nettype none

module zm_audio_pokey (
    input  wire        clk,
    input  wire        rst,
    input  wire        pal,
    input  wire        clock_wr,      // POKEY_CLOCK was written: restart the cycle count
    input  wire        we,
    input  wire [3:0]  addr,
    input  wire [7:0]  din,
    input  wire        silence,
    input  wire        strobe,        // run this sample's cycles
    output wire        busy,
    output reg  [11:0] sum = 12'd0,
    output reg  [5:0]  cnt = 6'd0
);
    // Cycles a sample: NUM / DEN, 40 + (one more when the remainder carries).
    // NUM - 40 DEN as constants (NTSC 3125 - 40 x 77, PAL 180200000 - 40 x 4481001): no multiply.
    localparam [27:0] NTSC_DEN = 28'd77, PAL_DEN = 28'd4481001;
    localparam [27:0] NTSC_OVER = 28'd45, PAL_OVER = 28'd959960;
    wire [27:0] den = pal ? PAL_DEN : NTSC_DEN;
    wire [27:0] over = pal ? PAL_OVER : NTSC_OVER;
    reg  [27:0] frac = 28'd0;                    // < den
    wire [28:0] t = {1'b0, frac} + {1'b0, over}; // 0 <= t < 2 den: 40 <= cycles <= 41
    wire        more = t >= {1'b0, den};

    reg  [2:0] quiet = 3'd0;          // silence: AUDC4, 3, 2, 1 to go
    reg        held = 1'b0;           // a write that came during a burst
    reg  [3:0] held_a = 4'd0;
    reg  [7:0] held_d = 8'd0;
    wire       idle = !busy;
    wire       q_wr = quiet != 3'd0 && idle;
    wire       h_wr = held && idle && !q_wr;
    wire       d_wr = we && idle && !q_wr && !h_wr;
    wire       wr = q_wr || h_wr || d_wr;
    wire [3:0] wa = q_wr ? {1'b0, quiet[1:0] - 2'd1, 1'b1} : h_wr ? held_a : addr;
    wire [7:0] wd = q_wr ? 8'd0 : h_wr ? held_d : din;

    reg  [5:0] left = 6'd0;           // the burst's cycles still to run
    reg        ran = 1'b0, taken = 1'b0;  // zm_pokey's `mix` is registered: a cycle's mix is there two clocks on
    reg  [11:0] acc = 12'd0;
    reg  [5:0]  n = 6'd0;
    wire       cen = left != 6'd0;
    wire [5:0] mix;
    zm_pokey #(.EXT_CEN(1)) u_pokey (
        .clk(clk), .rst(rst), .pal(pal), .cen_ext(cen), .we(wr), .addr(wa), .din(wd),
        .cen(), .level(), .mix(mix));

    assign busy = cen || ran || taken;
    always @(posedge clk) begin
        if (rst) begin
            {quiet, held, held_a, held_d, left, ran, taken, acc, n, sum, cnt, frac} <= 0;
        end else begin
            if (silence) quiet <= 3'd4;
            else if (q_wr) quiet <= quiet - 3'd1;
            if (we && !d_wr) {held, held_a, held_d} <= {1'b1, addr, din};
            else if (h_wr) held <= 1'b0;
            ran <= cen;
            taken <= ran;
            if (clock_wr) begin
                frac <= 28'd0;
            end else if (strobe) begin
                left <= more ? 6'd41 : 6'd40;
                frac <= more ? t[27:0] - den : t[27:0];
            end else if (cen) begin
                left <= left - 6'd1;
            end
            if (strobe) {acc, n} <= 0;
            else if (taken) {acc, n} <= {acc + {6'd0, mix}, n + 6'd1};
            if (taken && !ran) {sum, cnt} <= {acc + {6'd0, mix}, n + 6'd1};  // the burst's last cycle
        end
    end
endmodule

`default_nettype wire
