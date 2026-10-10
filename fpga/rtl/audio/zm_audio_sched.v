// The audio core's write queue: register writes stamped with the sample they
// land before, applied to zm_audio_core exactly there (docs/FPGA_AUDIO.md "The
// SoC"). The players run on the cart CPU ahead of the sound (cycles/baudio.c
// keeps them a few frames ahead) and stamp every chip call with its sample in
// the machine's stream (host/audio_imports.c); here each write waits for its
// sample. So the chips see the machine's writes, in program order, each at the
// machine's sample, however the CPU's time is spread over the frame.
//
// `now` counts the core's sample strobes: the strobe that starts sample n's mix
// finds now == n. A write stamped n is due once now == n (no later than the
// strobe that starts sample n), and it lands only between two mixes (`mixing`
// low), so it is heard from sample n on and never during sample n - 1's mix.
// One write leaves the queue every two clocks or so; a sample period is
// thousands. Pushed: {stamp[21:0], byte address[9:0]} then the data (32 bits).
//   late      a write landed after its sample (stamp < now when applied): the
//             firmware fell behind; sticky
//   overflow  a push found the queue full and was dropped; sticky
`default_nettype none

module zm_audio_sched #(
    parameter integer AW = 11              // 2^AW entries
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        push,
    input  wire [31:0] push_a,             // {stamp[21:0], addr[9:0]}
    input  wire [31:0] push_d,
    output wire [AW:0] level,
    input  wire        tick,               // zm_audio_core: a sample's mix starts
    input  wire        mixing,             // zm_audio_core: a mix runs, no write may land
    input  wire        core_ready,
    output wire        core_wr,
    output wire [9:0]  core_addr,
    output wire [31:0] core_wdata,
    output reg  [31:0] now = 32'd0,
    output reg         late = 1'b0,
    output reg         overflow = 1'b0,
    output reg  [31:0] applied = 32'd0,     // writes landed since reset
    input  wire        clear               // clears late and overflow
);
    reg  [AW-1:0] wptr = 0, rptr = 0;
    reg  [AW:0]   count = 0;
    wire          full = count[AW];
    wire          take = push && !full;
    wire [63:0]   head;
    zm_video_sdpram #(.AW(AW), .DW(64)) u_q (
        .clk(clk), .we({8{take}}), .waddr(wptr), .wdata({push_a, push_d}), .raddr(rptr), .rdata(head));

    // `head` is mem[rptr] one clock after rptr (and the entry) settled.
    reg         loaded = 1'b0;
    wire [21:0] stamp = head[63:42];
    wire [21:0] ahead = stamp - now[21:0];   // > 0: due later (mod 2^22, 95 s)
    wire        due = ahead == 22'd0 || ahead[21];
    wire        pop = loaded && due && !mixing && core_ready;
    assign core_wr = pop;
    assign core_addr = head[41:32];
    assign core_wdata = head[31:0];
    assign level = count;

    always @(posedge clk) begin
        if (rst) begin
            {wptr, rptr, count, loaded, late, overflow} <= 0;
            {now, applied} <= 0;
        end else begin
            if (take) wptr <= wptr + 1'b1;
            if (pop) rptr <= rptr + 1'b1;
            count <= count + take - pop;
            loaded <= !pop && count != 0;
            if (tick) now <= now + 32'd1;
            if (pop) applied <= applied + 32'd1;
            late <= clear ? 1'b0 : late | (pop && ahead != 22'd0);
            overflow <= clear ? 1'b0 : overflow | (push && full);
        end
    end
endmodule

`default_nettype wire
