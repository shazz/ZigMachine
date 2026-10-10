// The ym-test bitstream's sound, in the system clock domain: a YM register dump
// (tools/ym_rom.py: Drooling by 505) played by the lab's player
// (zm_dump_player) into the machine's audio core (rtl/audio/zm_audio_core.v),
// register r at core address 4r, one 50 Hz frame every 882 samples (as
// libs/zig/players/ym_player.zig does), a 44.1 kHz stereo sample out on
// `smp_valid`. The PCM channels stay idle (their memory port reads zeros).
// This is the chip half of a lab player: swap the core and the converter for
// another chip, keep rtl/board/snd_lab_out.v.
// The ROM is the define YM_ROM (default ym_rom.hex in yosys's directory: the
// Makefile writes it there with tools/ym_rom.py; tests/test_rtl_audio.py passes
// a path), its depth YM_WORDS (its line count).
`default_nettype none
`ifndef YM_ROM
`define YM_ROM "ym_rom.hex"
`endif
`ifndef YM_WORDS
`define YM_WORDS 22678
`endif

module ym_test_audio #(
    parameter         ROM = `YM_ROM,
    parameter integer WORDS = `YM_WORDS,
    parameter integer SR_INC = 441,          // 44.1 kHz and 2 MHz at 50 MHz
    parameter integer SR_MOD = 500000,
    parameter integer YM_INC = 1,
    parameter integer YM_MOD = 25
) (
    input  wire        clk,
    input  wire        rst,
    output wire        smp_valid,
    output wire [15:0] smp_l,
    output wire [15:0] smp_r,
    output wire [2:0]  status,
    output wire [15:0] pc
);
    // A frame tick at the start, then after every FRAME-th sample (50 Hz).
    localparam [9:0] FRAME = 882;
    reg [9:0] n = 10'd0;
    reg       first = 1'b1;
    wire      last = n == FRAME - 10'd1;
    wire      tick = first || (smp_valid && last);
    always @(posedge clk) begin
        if (rst) {n, first} <= {10'd0, 1'b1};
        else begin
            first <= 1'b0;
            if (smp_valid) n <= last ? 10'd0 : n + 10'd1;
        end
    end

    wire       wr, ready;
    wire [6:0] r;
    wire [7:0] v;
    zm_dump_player #(.ROM(ROM), .WORDS(WORDS)) u_player (
        .clk(clk), .rst(rst), .tick(tick), .chip_wr(wr), .chip_reg(r), .chip_val(v), .chip_ready(ready), .pc(pc));

    wire mem_req;
    zm_audio_core #(.SR_INC(SR_INC), .SR_MOD(SR_MOD), .YM_INC(YM_INC), .YM_MOD(YM_MOD)) u_core (
        .clk(clk), .rst(rst), .wr(wr), .addr(r[6:4] == 3'd0 ? {4'd0, r[3:0], 2'b00} : 10'h3FC),   // past R15: a field no one has
        .wdata({24'd0, v}), .rdata(), .ready(ready),
        .mem_req(mem_req), .mem_addr(), .mem_ack(mem_req), .mem_data(8'd0),
        .smp_valid(smp_valid), .smp_l(smp_l), .smp_r(smp_r), .status(status));
endmodule

`default_nettype wire
