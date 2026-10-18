// ZIGGY cost model: what one wasm instruction costs on the board, in CPU cycles.
//
// IT IS AN ESTIMATE. The board runs the cart as wasm2c C compiled by GCC for rv32imf
// (fpga/CYCLES.md, "aligned" build: one lw/sw per wasm access, no bounds checks), so a
// wasm op maps onto a small, predictable rv32 sequence; locals become registers. What
// the model cannot see: cache misses (D$ 4 KiB, I$ 16 KiB 2-way), GCC folding a compare
// into its branch, spills. Those are absorbed by CPI below, calibrated on board numbers.
//
// FITTED 2026-10-18 to MEASURED board frame times of 92 carts (glass-ctl ZMSTAT, 12-17 s
// after load; apps/perf_fit.mjs over the same window of each cart's board build):
// median error 4%, p90 ~35%. CPI is only weakly identified (the fit's loss is flat from
// 0.6 to 1.35: it trades against STORE_DRAIN through the roofline) and is pinned at 1.0;
// DMISS and HBL_CALL fall to their floor: the board shows no cost for them beyond what the
// instructions already carry. FRESCO_PLANE, FILL_WORD_CYCLES and STORE_DRAIN are well set.
//
// Earlier calibration points (2026-10-17 board tour, 100 MHz, 1.67 Mc per 60 Hz frame):
//   - empire's LogicalFB.clearFrameBuffer byte loop: ~2 Mc per 64,000-byte plane, i.e.
//     ~31 cycles a byte store when stores come back to back -> STORE_DRAIN.
//     (The 8-entry store buffer hides a store only while the code between stores is
//     longer than the drain; a tight store loop runs at the drain rate.)
//   - Joust 5.53 Mc -> ~0.8 Mc cart per frame (perf/joust-board), 18 -> 60 fps.
//   - compiler-rt sinf ~1,700 instructions (its f64 path, soft-float) against ~125 for
//     libs/zig/libm_f32.zig: the f64 costs below put sinf in that range.
//   - soft-float routine costs: libgcc on rv32 (fpga/CYCLES.md "FPU estimate" for the f32
//     FPU column: add/mul 5 dependent, div 18, sqrt 30; f64 has no hardware).
//   - CHISEL: ~400 CPU clocks a call (start, spin, D$ flush) + clocks per CYCLES unit by
//     op (docs/BLITTER_HW_SPEC.md 10.5: FILL 1.03, keyed BLIT 0.9-2.2, TRIANGLE 4.6-6.1);
//     the CPU spins on BUSY, so blitter time is cart time.

export const CPI = 1.0;           // cycles per modelled rv32 instruction (board fit: weakly identified)
export const STORE_DRAIN = 27;    // cycles per store while the store buffer is full (board fit; empire's old clear said ~31)
// CPU cycles per hwBlit beyond the blitter's own time: start + spin, and the FULL D$
// invalidate fpga/cycles/bblit.c does after every op (128 lines of a 4 KiB D$, and the
// cart's working set misses again after it). BLIT_DFLUSH is the part a range flush
// (perf/blit-dcache-range) would remove; tiny_blits charges it as the waste of a tiny op.
export const BLIT_START = 150;
export const BLIT_DFLUSH = 30;    // since 7993ff78 bblit.c invalidates only the op's lines (was ~250: the whole D$)
export const BLIT_CALL = BLIT_START + BLIT_DFLUSH;
// clocks per CYCLES unit by COMMAND (1 BLIT, 2 FILL, 3 LINE, 4 TRIANGLE), plain vs
// read-modify-write (the minterm reads the destination C): BLITTER_HW_SPEC 10.5 and the
// board-SoC sims of tsl_hybridglenz (1.24 Mc cart: 120 K fill + 107 K triangle units) and
// fuji_hobbytronic (0.76: 64 K fill + 8.5 K triangle), solved together: DDR is shared with FRESCO.
export const BLIT_UNIT = [0, 2.0, 1.85, 1.9, 9.2];
export const BLIT_UNIT_RMW = [0, 7.7, 7.7, 7.7, 9.2];
const readsDest = (minterm) => ((minterm ^ (minterm >> 1)) & 0x55) !== 0;
export const blitCycles = (cmd, units, minterm) =>
    BLIT_CALL + units * ((readsDest(minterm) ? BLIT_UNIT_RMW : BLIT_UNIT)[cmd] ?? 1.5);
// FRESCO paints each ENABLED plane in a pass the CPU waits for (cycles/bmain.c: the plane
// passes follow cart.frame): 0.77-0.82 Mc a plane in the board-SoC sim logs (ZM QF); the
// board fit says ~1.09 Mc. Empty planes cost the same.
export const FRESCO_PLANE = 1.09e6;
export const HBL_CALL = 0;     // per hblDispatch beyond the handler's own instructions (board fit: ~0)
export const DISK_BLOCK = 0;  // cycles per 512-byte disk block read (the board's firmware copies it out of DDR)
// Palette stores past the compositor's 16-entry snoop queue within one HBL handler
// (soc/zm_video_snoop.py). First fitted at 1,900 to the old stcs alone (1 fps on the
// board); the 2026-10-18 board table REFUTES that: snyd_90 makes 1,556 such stores a frame
// and runs 60 fps. The fit puts the cost at ~240 cycles; the old stcs stays unexplained.
// A misaligned lw/sw on the board's `aligned` build traps (fpga/cycles/trap.S: 30 registers saved
// and restored on the write-through stack, then the access redone byte by byte). A fit to the
// board fps of naos_nitrowave (24,662 misaligned a frame, 129 ms) and ics (12,207, 105 ms).
export const TRAP_CYCLES = 450;
export const SNOOP_QUEUE = 16;
export const SNOOP_OVERFLOW = 240; // cycles per palette store beyond the queue, within one handler
// memset/memcpy (wasm memory.fill/copy -> picolibc) cost per 32-bit word ON THE BOARD:
// first fitted to empire and maxi alone (~86 a word), then to the 92-cart board table: ~60
// a word, against ~27 a store for a byte loop. A memset is ~2x a byte loop on ZIGGY; a
// CHISEL fill is ~1.85 clocks a byte.
export const FILL_WORD_CYCLES = 60;
// I$ (16 KiB, 2-way): when the rv32 code a frame runs is bigger, a share of its
// instruction fetches miss; a miss refills a 32-byte line (8 instructions) in ~40 cycles.
// Joust (~24 KB a frame) is where this shows: without it the model is ~2x under its sim.
export const ICACHE = 16384;
export const ICACHE_MISS_CPI = 5;
export const icacheCycles = (instr, codeBytes) => instr * ICACHE_MISS_CPI * Math.max(0, 1 - ICACHE / Math.max(1, codeBytes));
export const CONST_DIV = 5;      // i32 divide by a constant (mulhu + shifts); i64: 4x
// A D$ miss (4 KiB direct-mapped, 32-byte lines, modelled on the cart's real load stream by
// probe_hooks.mjs): a line refill from DDR over HP0, the first word ~24-62 cycles late
// (fpga/CYCLES.md "Memory path") plus the burst. The board fit puts it at its floor (10):
// the misses the model sees are already paid for inside CPI.
export const DMISS = 10;
export const MHZ = 100;
export const FRAME_MC = MHZ / 60; // 1.667 Mc: a 60 Hz frame

// op class names, in report order
export const CLASSES = ["narrow_store", "store32", "store64", "f64", "f32_divsqrt", "f32", "i32_div",
    "i64_mul", "i64_div", "i64_shift", "i64_other", "load", "call", "libm_call", "unaligned"];
// "unaligned" is a COUNT, not a cost (no cycles in the estimate): loads/stores wider than a byte
// whose memarg alignment hint is below their width. The board's `aligned` build turns every one
// into a single lw/sw, and a MISALIGNED address traps (fpga/cycles/trap.c: ~1,000 cycles each,
// registers saved to the write-through stack). Zig emits the hint from the pointer type, so a
// u32 read out of a byte buffer (an emulated 68000's RAM) shows here; a u32 array does not.

const C = Object.fromEntries(CLASSES.map((c, i) => [c, i]));
export const CLS = C;

// [rv32 instructions, class or -1, bus stores]
function table() {
    const t = new Map();
    const set = (ops, cyc, cls = -1, st = 0) => { for (const o of [].concat(ops)) t.set(o, [cyc, cls, st]); };
    const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);
    set([0x00, 0x01, 0x02, 0x03, 0x05, 0x0b, 0x1a], 0);
    set([0x0c, 0x0d, 0x04, 0x0f], 1); set(0x0e, 5); set(0x1b, 2); set(0x1c, 2);
    set([0x20, 0x21, 0x22], 0.2); set(0x23, 1); set(0x24, 1, C.store32, 1);
    set(range(0x28, 0x35), 2, C.load); set([0x29, 0x2b], 3, C.load);
    set([0x36, 0x38, 0x3e], 2, C.store32, 1); set([0x3a, 0x3b, 0x3c, 0x3d], 2, C.narrow_store, 1);
    set([0x37, 0x39], 3, C.store64, 2);
    set(0x3f, 2); set(0x40, 50); set(0x41, 0.4); set(0x42, 0.8); set(0x43, 2); set(0x44, 2, C.f64);
    set(range(0x45, 0x4f), 1); set(range(0x6a, 0x78), 1); set([0x67, 0x68], 12); set(0x69, 20);
    set(range(0x6d, 0x70), 35, C.i32_div);
    set(0x50, 2, C.i64_other); set(range(0x51, 0x5a), 4, C.i64_other); set([0x79, 0x7a, 0x7b], 12, C.i64_other);
    set([0x7c, 0x7d], 4, C.i64_other); set([0x83, 0x84, 0x85], 2, C.i64_other); set(0x7e, 8, C.i64_mul);
    set(range(0x7f, 0x82), 250, C.i64_div); set(range(0x86, 0x8a), 7, C.i64_shift);
    set(range(0x5b, 0x60), 2, C.f32); set([0x8b, 0x8c, 0x98], 1, C.f32); set(range(0x8d, 0x90), 12, C.f32);
    set([0x92, 0x93, 0x94], 3, C.f32); set([0x96, 0x97], 2, C.f32); set(0x95, 18, C.f32_divsqrt); set(0x91, 30, C.f32_divsqrt);
    set(range(0x61, 0x66), 40, C.f64); set([0x99, 0x9a, 0xa6], 3, C.f64); set(range(0x9b, 0x9e), 70, C.f64);
    set([0xa0, 0xa1], 90, C.f64); set(0xa2, 110, C.f64); set(0xa3, 450, C.f64); set(0x9f, 700, C.f64);
    set([0xa4, 0xa5], 40, C.f64);
    set(0xa7, 0.5); set([0xac, 0xad], 1, C.i64_other); set([0xa8, 0xa9, 0xb2, 0xb3], 3, C.f32);
    set([0xae, 0xaf, 0xb4, 0xb5], 70, C.f32); set([0xaa, 0xab, 0xb7, 0xb8, 0xb6, 0xbb], 50, C.f64);
    set([0xb0, 0xb1, 0xb9, 0xba], 120, C.f64); set([0xbc, 0xbe], 1); set([0xbd, 0xbf], 2, C.f64);
    set(range(0xc0, 0xc4), 1);
    set([0xfc00, 0xfc01, 0xfc04, 0xfc05], 3, C.f32); set([0xfc02, 0xfc03, 0xfc06, 0xfc07], 50, C.f64);
    set([0xfc08, 0xfc09, 0xfc0a, 0xfc0b], 20); // + the bytes, counted at run time
    set([0x10, 0x12], 6, C.call); set([0x11, 0x13], 12, C.call);
    set([0xd0, 0xd1, 0xd2, 0x25, 0x26], 2);
    return t;
}
const COST = table();

export function opCost(op) {
    const c = COST.get(op);
    if (!c) return [2, -1, 0]; // unlisted (reference/table ops): a guess, never seen in carts
    return c;
}

// Run-time bytes of memory.fill / memory.copy, as cycles (word loop, bus-bound on stores).
export const fillCycles = (bytes) => (bytes / 4) * FILL_WORD_CYCLES;
export const copyCycles = (bytes) => (bytes / 4) * FILL_WORD_CYCLES;

// A region's cycles for one frame: its instructions, or its store stream if that is
// the slower of the two (the roofline of a loop against the store buffer's drain).
export const regionCycles = (instr, stores) => Math.max(instr * CPI, stores * STORE_DRAIN);

const LIBM = /^(a?sin|a?cos|a?tan|atan2|sinh|cosh|tanh|exp2?|expm1|log(2|10|1p)?|pow|fmod|hypot|cbrt|sincos|floor|ceil|round|trunc|sqrt|fma|ldexp|frexp|modf|rem_pio2(_large)?|k_(sin|cos|tan))f?$/;
// libm-ish by the last component of a mangled name: "math.sin.sin", "sinf", "__sin"
export function isLibm(name) {
    if (!name) return false;
    const last = name.split(/[.:]/).pop().replace(/^_+/, "");
    return LIBM.test(last);
}

// cause buckets: which classes feed each
export const CAUSES = {
    f64: ["f64"], div: ["i32_div", "i64_div"], i64: ["i64_mul", "i64_shift", "i64_other"],
    f32: ["f32_divsqrt"], calls: ["call"],
};
