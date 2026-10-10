// The machine's sound hardware in the system clock domain: the YM2149
// (zm_audio_ym: jt49), the four Paula channels (zm_audio_pcm) and the machine's
// mix (zm_audio_mix), one stereo 16-bit sample every `SR_INC / SR_MOD` clocks
// (44.1 kHz at 50 MHz: 441 / 500000) on `smp_valid`. The YM's 2 MHz is
// `YM_INC / YM_MOD` of the clock (1 / 25 at 50 MHz). Both are exact fractions
// of the same clock, so the HDMI side (zm_hdmi_acr, on a clock from the same
// crystal) takes samples at exactly the rate they are made.
//
// The registers mirror the sealed audio ABI (machine/sdk/audio.zig); the map is
// in docs/FPGA_AUDIO.md. Byte addresses, 32-bit words:
//   0x000 + 4r  YM register r (machineYmWrite; R13 = 0xFF does not retrigger the
//               envelope and is not passed on, as ym.zig); reads the last value
//   0x040       CTRL: write bit 0 = machineAudioReset (mixer off, A/B/C volume 0,
//               every channel stopped)
//   0x044       STATUS (read; any write clears): bit 0 a wrap overran (pcm),
//               bit 1 a YM count without a K (mix), bit 2 a sample came late
//   0x048       VERSION: 0x00010100, ZM_AUDIO_VERSION
//   0x100 + 0x40c + 4f  channel c, field f (zm_audio_pcm): DATA, LEN, LOOP_START,
//               LOOP_LEN (staged for TRIGGER), STEP, VOLUME, PAN, POS, CTRL
// A write is taken on a clock with `wr` and `ready`; `ready` drops for the clock
// after a YM write (jt49 needs the gap) and for the 8 clocks of a reset.
// `tick` and `mixing` let a writer (zm_audio_sched) land each write between two
// samples' mixes, at the sample it was stamped for.
`default_nettype none

module zm_audio_core #(
    parameter integer SR_INC = 441,
    parameter integer SR_MOD = 500000,
    parameter integer YM_INC = 1,
    parameter integer YM_MOD = 25
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        wr,
    input  wire [9:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        ready,
    output wire        mem_req,
    output wire [31:0] mem_addr,
    input  wire        mem_ack,
    input  wire [7:0]  mem_data,
    output wire        smp_valid,
    output wire [15:0] smp_l,
    output wire [15:0] smp_r,
    output wire [2:0]  status,
    output wire        tick,             // the sample strobe: sample n's mix starts (zm_audio_sched counts these)
    output wire        mixing            // the strobe or the PCM mix is running: no write may land now
);
    wire strobe, ym_cen;
    zm_audio_frac #(.INC(SR_INC), .MOD(SR_MOD)) u_sr (.clk(clk), .rst(rst), .tick(strobe));
    zm_audio_frac #(.INC(YM_INC), .MOD(YM_MOD)) u_ymclk (.clk(clk), .rst(rst), .tick(ym_cen));

    // --- the bus
    reg  [3:0] seq = 4'd0;               // machineAudioReset: 4 YM writes, 2 clocks apart
    reg        gap = 1'b0;
    assign ready = !gap && seq == 4'd0;
    wire       take = wr && ready;
    wire       is_ym = addr[9:6] == 4'd0;
    wire       is_ch = addr[9:8] == 2'd1;
    wire       ym_bus = take && is_ym && !(addr[5:2] == 4'd13 && wdata[7:0] == 8'hFF);
    wire       reset_cmd = take && addr == 10'h040 && wdata[0];

    reg  [7:0] shadow [0:15];
    // seq 8, 6, 4, 2: R7 = 0x3F, then R8, R9, R10 = 0 (machineAudioReset's order).
    wire       seq_wr = seq != 4'd0 && !seq[0];
    wire [3:0] seq_reg = 4'd11 - seq[3:1];
    wire       ym_wr = ym_bus || seq_wr;
    wire [3:0] ym_addr = seq_wr ? seq_reg : addr[5:2];
    wire [7:0] ym_din = seq_wr ? (seq == 4'd8 ? 8'h3F : 8'h00) : wdata[7:0];
    always @(posedge clk) begin
        if (rst) {seq, gap} <= 0;
        else begin
            gap <= ym_bus;
            seq <= reset_cmd ? 4'd8 : (seq != 4'd0) ? seq - 4'd1 : 4'd0;
        end
        if (ym_wr || (take && is_ym)) shadow[ym_addr] <= ym_din;   // R13 = 0xFF is kept, as ym.zig
    end

    // --- the chips and the mix
    wire [15:0] ym_sum;
    wire [6:0]  ym_cnt;
    zm_audio_ym u_ym (
        .clk(clk), .rst(rst), .ym_cen(ym_cen), .wr(ym_wr), .addr(ym_addr), .din(ym_din),
        .strobe(strobe), .sum(ym_sum), .cnt(ym_cnt));

    wire        pcm_done, overrun;
    wire signed [27:0] acc_l, acc_r;
    wire [31:0] ch_rd;
    reg         pcm_busy = 1'b0, late = 1'b0;
    zm_audio_pcm u_pcm (
        .clk(clk), .rst(rst), .we(take && is_ch), .wch(addr[7:6]), .wf(addr[5:2]), .wd(wdata),
        .silence(reset_cmd), .rd(ch_rd), .start(strobe && !pcm_busy), .done(pcm_done),
        .acc_l(acc_l), .acc_r(acc_r), .overrun(overrun),
        .mem_req(mem_req), .mem_addr(mem_addr), .mem_ack(mem_ack), .mem_data(mem_data));

    wire bad_cnt;
    zm_audio_mix u_mix (
        .clk(clk), .rst(rst), .start(pcm_done), .pcm_l(acc_l), .pcm_r(acc_r), .ym_sum(ym_sum), .ym_cnt(ym_cnt),
        .valid(smp_valid), .out_l(smp_l), .out_r(smp_r), .bad_cnt(bad_cnt));

    // --- status: sticky here (the blocks pulse), cleared by any write to STATUS
    reg [1:0] seen = 2'd0;
    wire      clear = take && addr == 10'h044;
    always @(posedge clk) begin
        if (rst) {pcm_busy, late, seen} <= 0;
        else begin
            pcm_busy <= strobe ? 1'b1 : pcm_done ? 1'b0 : pcm_busy;
            late <= clear ? 1'b0 : late | (strobe && pcm_busy);
            seen <= clear ? 2'd0 : seen | {bad_cnt, overrun};
        end
    end
    assign status = {late, seen};
    assign tick = strobe;
    assign mixing = strobe || pcm_busy;

    always @(*) begin
        rdata = 32'd0;
        if (is_ym) rdata = {24'd0, shadow[addr[5:2]]};
        else if (addr == 10'h044) rdata = {29'd0, status};
        else if (addr == 10'h048) rdata = 32'h00010100;
        else if (is_ch) rdata = ch_rd;
    end
endmodule

`default_nettype wire
