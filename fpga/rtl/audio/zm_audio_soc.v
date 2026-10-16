// The machine's sound in the board SoC: zm_audio_core fed by zm_audio_sched,
// behind a register window on the cart CPU's bus (soc/zm_audio_soc.py maps it at
// AUDIO_WINDOW, outside every seal window: only the firmware reaches it). The
// firmware runs the players (the SNDH player on Musashi) and pushes their chip
// calls here as stamped register writes; the core renders 44.1 kHz stereo, its
// PCM bytes fetched through `mem_*` (the players' memory in DDR, over HP3).
// Word registers (byte offset = 4 x word):
//   0 QA        W  {stamp[21:0], core byte address[9:0]} of the next write
//   1 QD        W  its data: pushes {QA, QD}
//   2 NOW       R  samples started since reset (zm_audio_sched `now`)
//   3 LEVEL     R  writes queued
//   4 STATUS    R  {core status[2:0], overflow, late}; any write clears late/overflow
//   5 PCM_BASE  RW the bus byte address of the players' memory (PCM DATA addresses are in it)
//   6 APPLIED   R  writes landed since reset
//   7 ID        R  0x5A410100 ("ZA", 1.0)
`default_nettype none

// keep_hierarchy: without it Vivado optimises zm_audio_sched/zm_audio_pcm across this boundary
// and lands on one of two shapes (~1,795 or ~1,965 LUT) depending on unrelated changes elsewhere.
(* keep_hierarchy = "yes" *)
module zm_audio_soc #(
    parameter integer SR_INC = 441,
    parameter integer SR_MOD = 1000000,    // 44.1 kHz at 100 MHz
    parameter integer YM_INC = 1,
    parameter integer YM_MOD = 50,         // 2 MHz at 100 MHz
    parameter integer QAW = 11
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        bus_wr,
    input  wire [2:0]  bus_addr,           // word
    input  wire [31:0] bus_wdata,
    output reg  [31:0] bus_rdata,
    output wire        mem_req,
    output wire [31:0] mem_addr,
    input  wire        mem_ack,
    input  wire [7:0]  mem_data,
    output reg  [31:0] pcm_base = 32'd0,
    output wire        smp_valid,
    output wire [15:0] smp_l,
    output wire [15:0] smp_r,
    output wire        core_wr,            // a write landing (the sim's tap: soc/zm_audio_soc.py)
    output wire [9:0]  core_addr,
    output wire [31:0] core_wdata,
    output wire [31:0] now
);
    reg  [31:0] qa = 32'd0;
    wire [QAW:0] level;
    wire        tick, mixing, ready, late, overflow;
    wire [2:0]  status;
    wire [31:0] applied;
    zm_audio_sched #(.AW(QAW)) u_sched (
        .clk(clk), .rst(rst), .push(bus_wr && bus_addr == 3'd1), .push_a(qa), .push_d(bus_wdata),
        .level(level), .tick(tick), .mixing(mixing), .core_ready(ready), .core_wr(core_wr),
        .core_addr(core_addr), .core_wdata(core_wdata), .now(now), .late(late), .overflow(overflow),
        .applied(applied), .clear(bus_wr && bus_addr == 3'd4));

    zm_audio_core #(.SR_INC(SR_INC), .SR_MOD(SR_MOD), .YM_INC(YM_INC), .YM_MOD(YM_MOD)) u_core (
        .clk(clk), .rst(rst), .wr(core_wr), .addr(core_addr), .wdata(core_wdata), .rdata(), .ready(ready),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ack(mem_ack), .mem_data(mem_data),
        .smp_valid(smp_valid), .smp_l(smp_l), .smp_r(smp_r), .status(status), .tick(tick), .mixing(mixing));

    always @(posedge clk) begin
        if (rst) {qa, pcm_base} <= 0;
        else if (bus_wr) begin
            if (bus_addr == 3'd0) qa <= bus_wdata;
            if (bus_addr == 3'd5) pcm_base <= bus_wdata;
        end
    end

    always @(*) begin
        case (bus_addr)
            3'd0: bus_rdata = qa;
            3'd2: bus_rdata = now;
            3'd3: bus_rdata = {{(31 - QAW){1'b0}}, level};
            3'd4: bus_rdata = {27'd0, status, overflow, late};
            3'd5: bus_rdata = pcm_base;
            3'd6: bus_rdata = applied;
            3'd7: bus_rdata = 32'h5A410100;
            default: bus_rdata = 32'd0;
        endcase
    end
endmodule

`default_nettype wire
