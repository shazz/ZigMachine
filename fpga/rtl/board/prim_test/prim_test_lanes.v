// The primitive self-test's lanes (rtl/board/prim_test_top.v): one per primitive
// and mode the SoC's netlist uses, plus the modes under suspicion. The comment
// on each is what Yosys maps it to (tools/prim_allowlist.py's key, checked by
// tests/test_prim_allowlist.py). tools/prim_test_read.py's LANES names them in
// this order: keep the two in step.
`default_nettype none

module prim_test_lanes #(
    parameter integer BREAK_TEST = -1,  // a lane whose reference has bit 0 inverted (break tests)
    parameter integer NL = 45           // the lane count: not a knob, the list below is fixed
) (
    input  wire              clk,
    input  wire              start,
    input  wire              clear,
    input  wire [31:0]       seed,
    output wire [NL-1:0]     done,
    output wire [NL*224-1:0] res
);
    function [95:0] flip(input integer i);
        flip = (BREAK_TEST == i) ? 96'd1 : 96'd0;
    endfunction

`define PT_LANE(i) .clk(clk), .start(start), .clear(clear), .done(done[i]), .res(res[(i)*224 +: 224])
`define PT_RAM(name, i, aw, dw, st, maw, base, bw) \
    prim_ram_test #(.AW(aw), .DW(dw), .STYLE(st), .MAW(maw), .ABASE(base), .BW(bw), .FLIP(flip(i))) \
        name (`PT_LANE(i), .seed(seed));
    // SDP block RAMs: x72 (bad on silicon), x36 at 512 and 256 words and at other addresses, byte enables
    `PT_RAM(l0, 0,  9,  72, 0, 9,  0,   72)  // RAMB36 SDP x72
    `PT_RAM(l1, 1,  8,  72, 0, 8,  0,   72)  // 256 x 72
    `PT_RAM(l2, 2,  9,  72, 0, 9,  0,   9)   // RAMB36 SDP x72, 8 byte enables
    `PT_RAM(l3, 3,  9,  36, 0, 9,  0,   36)  // RAMB18 SDP x36
    `PT_RAM(l4, 4,  8,  36, 0, 8,  0,   36)  // 256 x 36
    `PT_RAM(l5, 5,  8,  36, 0, 9,  256, 36)  // 512 x 36, words 256-511 used
    `PT_RAM(l6, 6,  7,  36, 0, 9,  384, 36)  // 512 x 36, words 384-511 used
    `PT_RAM(l7, 7,  9,  36, 0, 9,  0,   9)   // RAMB18 SDP x36, 4 byte enables
    `PT_RAM(l8, 8,  9,  32, 0, 9,  0,   8)   // 512 x 32, 4 8-bit byte enables (a CPU's)
    // TDP block RAMs (one port writes, the other reads), each width
    `PT_RAM(l9, 9,  14, 1,  0, 14, 0,   1)   // RAMB18 x1
    `PT_RAM(l10, 10, 13, 2,  0, 13, 0,   2)   // RAMB18 x2
    `PT_RAM(l11, 11, 12, 4,  0, 12, 0,   4)   // RAMB18 x4
    `PT_RAM(l12, 12, 11, 9,  0, 11, 0,   9)   // RAMB18 x9
    `PT_RAM(l13, 13, 10, 18, 0, 10, 0,   18)  // RAMB18 x18
    `PT_RAM(l14, 14, 10, 18, 0, 10, 0,   9)   // RAMB18 x18, 2 byte enables
    `PT_RAM(l15, 15, 15, 1,  0, 15, 0,   1)   // RAMB36 x1
    `PT_RAM(l16, 16, 14, 2,  0, 14, 0,   2)   // RAMB36 x2
    `PT_RAM(l17, 17, 13, 4,  0, 13, 0,   4)   // RAMB36 x4
    `PT_RAM(l18, 18, 12, 9,  0, 12, 0,   9)   // RAMB36 x9
    `PT_RAM(l19, 19, 11, 18, 0, 11, 0,   18)  // RAMB36 x18
    `PT_RAM(l20, 20, 10, 36, 0, 10, 0,   36)  // RAMB36 x36
    `PT_RAM(l21, 21, 10, 36, 0, 10, 0,   9)   // RAMB36 x36, 4 byte enables
    // one port: write-first, read-first; a ROM
    `PT_RAM(l22, 22, 11, 18, 2, 11, 0,   9)   // RAMB36 x18, WRITE_FIRST, 2 byte enables (VexRiscv's)
    `PT_RAM(l23, 23, 11, 18, 1, 11, 0,   18)  // RAMB36 x18, READ_FIRST
    prim_rom_test #(.FLIP(flip(24))) l24 (`PT_LANE(24));  // RAMB18 x9, read only, contents in the bitstream
    // LUTRAMs, shift registers
    `PT_RAM(l25, 25, 5,  12, 0, 5,  0,   12)  // RAM32M
    `PT_RAM(l26, 26, 6,  6,  0, 6,  0,   6)   // RAM64M
    prim_srl_test #(.N(16), .FLIP(flip(27))) l27 (`PT_LANE(27), .seed(seed));  // SRL16E
    prim_srl_test #(.N(32), .FLIP(flip(28))) l28 (`PT_LANE(28), .seed(seed));  // SRLC32E
    // DSP48E1 configurations (prim_dsp_test.v), CARRY4, MUXF7/F8
    genvar d;
    generate
        for (d = 0; d < 11; d = d + 1) begin : dsp
            prim_dsp_test #(.MODE(d), .FLIP(flip(29 + d))) lane (`PT_LANE(29 + d), .seed(seed));
        end
    endgenerate
    prim_carry_test #(.FLIP(flip(40))) l40 (`PT_LANE(40), .seed(seed));
    prim_muxf_test #(.FLIP(flip(41))) l41 (`PT_LANE(41), .seed(seed));
    // more byte-enable shapes (board 2026-10-04: x18 with byte enables lost byte lanes)
    `PT_RAM(l42, 42, 11, 18, 0, 11, 0,   9)   // RAMB36 TDP x18, 2 byte enables
    `PT_RAM(l43, 43, 10, 16, 0, 10, 0,   8)   // RAMB18 TDP x18, 16 bits, 2 8-bit byte enables
    `PT_RAM(l44, 44, 10, 32, 0, 10, 0,   8)   // RAMB36 TDP x36, 32 bits, 4 8-bit byte enables
`undef PT_RAM
`undef PT_LANE
endmodule

`default_nettype wire
