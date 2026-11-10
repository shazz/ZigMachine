# ASTROLABE: an f64 coprocessor for KESTREL (SPIKE)

Status: **spike, 9 Nov 2026**, branch `spike/arm-fpu-coproc`. Built and tested off the board (machine,
RTL, firmware protocol, glass, a bench cart); **nothing here is measured on the board yet**: every board
figure below marked *est.* is an estimate to be replaced by `glass astro-bench` and the ASTRO BENCH cart.
Codename ASTROLABE, ASTRO in registers and the API (Matt, 9 Nov). It joins the chip family tables only
once proven on the board.

Matt, 9 Nov: "prepare a spike with the BRAM mailbox, so like a real coprocessor with its strengths and
drawbacks, use the ziggy f32 for good enough precision fast calcs, use the arm fpu for big batches,
better precision".

## 1. The idea

The Mega ST's SFP004 put a 68881 beside the 68000, reached through a handful of memory-mapped
registers: the 68000 wrote an operand and a command word, polled a response register, read the result.
Slow per operation, but it made double precision and transcendental functions possible on a machine
with none.

KESTREL has the same shape. ZIGGY (the cart CPU, VexRiscv rv32im, an f32 FPU on some bitstreams) has no
f64 hardware: every `f64` op is soft-float, ~50-150 cycles for an add or mul, hundreds for a divide,
thousands for a `sin`. An f64 FPU in ZIGGY does not fit the 7010 (15,716 / 17,600 LUT, 72 / 80 DSP
used). But the Zynq's ARM Cortex-A9 has VFPv3 (f64 in hardware) and a second core that Linux barely
uses. ASTROLABE makes it a coprocessor:

- **ZIGGY f32 for fast, good-enough maths** (every frame, per pixel, per vertex: still fixed point and
  f32, CLAUDE.md "Float math");
- **ASTROLABE for f64 and for batches**: a cart describes the work, one call hands it to the ARM.

## 2. What a cart sees: `env.hwAstro` (HW 1.18.0)

A machine instruction, like `hwBlit`: `hwAstro(desc, count) u32` runs `count` descriptors laid end to
end at cart address `desc`, in order, synchronously. Each descriptor is 80 bytes in the cart's own
memory (`machine/sdk/astro.zig`); the machine writes its status and scalar result back. The answer is
the first non-OK status, else 0. A refused descriptor writes nothing but its status; the others still
run (a batch is not a transaction).

| word | name | |
|---|---|---|
| 0 | OP | op (low 16) \| TYPE_F32_IN (bit 16: A, B are f32) \| TYPE_F32_OUT (bit 17: C is f32) |
| 1 | N | elements; GEMV columns; GEFA/GESL order |
| 2 | M | GEMV rows; MAP's function (FN_SIN, COS, TAN, EXP, LOG, SQRT, ATAN) |
| 3 | LDA | leading dimension, in elements (column-major, LINPACK's layout) |
| 4-6 | A, B, C | cart addresses of the arrays (GEFA/GESL: B = the i32 pivots, GESL: C = b, solved in place) |
| 8 | STATUS | written: ST_OK 0, BAD_OP 1, RANGE 2, ALIGN 3, BAD_DESC 4, TIMEOUT 5 (board) \| SERVED_ARM (bit 8) |
| 9 | CYCLES | written: ZIGGY cycles the whole call took, on the board (0 elsewhere) |
| 10-15 | S0, S1, S2 | f64 scalar operands (AXPY/SCAL's alpha is S0, FMA's addend S2) |
| 16-17 | R | f64 result (scalar ops, DOT; GEFA: 0, or 1 + a zero pivot's column) |

The ops: **scalar** `NOP` (the round trip alone), `ADD SUB MUL DIV SQRT FMA`, `SIN COS TAN ATAN2 EXP
LOG POW`; **vector** `VADD VMUL AXPY DOT SCAL MAP` (MAP = a libm function over an array); **matrix**
`GEMV`, LINPACK's `GEFA` (dgefa) and `GESL` (dgesl, job 0). Arithmetic is always f64; an f32 array is
widened on load and rounded once on store (so an f32-in, f32-out batch is *more* precise than ZIGGY's
f32 FPU doing the same chain). Limits: 48 descriptors a call, 2^20 elements a vector, order 1024.

From Zig: `zg.astro` (`libs/zig/astro.zig`): `zg.astro.sin(x)`, `zg.astro.run(&descs)` with builders
`daxpy dot dgemv map dgefa dgesl`. From C: `apps/c/scenes/astro_bench/astro.h`.

**The rule for a cart**: f32 and fixed point on ZIGGY for anything per frame that is good enough there;
ASTROLABE for what needs f64 or comes in arrays. A single `ADD` through ASTROLABE is a bad trade on the
board (§5); 48 of them in one call, or one `MAP` over 4096 elements, is the point.

**A soft-float hook?** Routing a cart's own `f64` division or `sin` to ASTROLABE transparently is not
possible: those are compiler_rt routines inside the cart's own wasm. The option is opt-in at the source:
`zg.astro.div/sqrt/sin/pow` (one call each), or better a batch. A later step could add a ZigOS
`f64` math module that a scene imports in place of `std.math` for its init-time tables.

## 3. Every host runs the same kernels

`machine/astro_ops.zig`, `astro_blas.zig`, `astro_linpack.zig` are ONE source, compiled four ways:

| host | who computes | latency |
|---|---|---|
| browser | the machine (`machine-video.wasm`'s `hwAstro`, bound by `docs/sealed-loader.js`) | a wasm call |
| native host | the same machine, wasm2c'd | a C call |
| board, ASTROLABE bitstream + glass | the ARM's VFPv3: glass links `machine/astro_ops.zig` | the round trip, §5 |
| board, fallback | ZIGGY: the machine's own code (soft f64), wrapped by the firmware | soft-float |

`@sin` & co. are compiler_rt's on every one (glass links no libc maths), and the IEEE ops are correctly
rounded everywhere, so **a result is the same bits on every host**: the bench checks 0 ulp against the
cart's own f64 for add, mul, div, sqrt and sin, and LINPACK's solution bit for bit against the cart's own
netlib `dgefa`/`dgesl` (same operations, same order). So a scene that `scene_hash.mjs` pins may use
ASTROLABE freely: unlike a JS `Math.sin` in the page, it never makes the board's frame differ.
(The page's JS is NOT the reference: `Math.sin(0.5)` happens to match; JS libm is allowed 1 ulp.)

## 4. The board: a 4 KB mailbox

```
 ZIGGY (cart CPU)                       PL                              ARM core 1 (glass)
 env.hwAstro(desc, n)            zm_astro_mbox.v: 1 RAMB36            astro.zig: pinned thread
   cycles/bastro.c  --Wishbone--> port A  0x9400_0000      port B <--GP0 0x43C0_2000-- astro_box.zig
   copy inputs, SEQ                      1024 words                  poll SEQ, TAKEN, stage arrays,
   wait TAKEN, DONE                                                  run kernels (VFPv3), DONE
   copy results <-------- cart's arrays stay in DDR (HP0) -------- read/written via /dev/mem (uncached)
```

- **The RAM** (`rtl/glass/zm_astro_mbox.v`, `soc/zm_astro.py`, z7 build flag `--astro`): one RAMB36,
  two ports, both in `sys`. ZIGGY's port is a Wishbone slave in the uncached IO space; the ARM's is the
  glass block's page `OFF_ASTRO = 0x2000` (zm_glass_regs forwards it; no new AXI slave, no PS7 change).
  READ_FIRST: a read that meets the other port's write returns the old word whole. No register logic,
  no DSP. `STATUS.ASTRO` (video STATUS bit 8) says the bitstream has it.
- **The words** (`glass/src/astro_box.zig` = `cycles/bastro_box.h`, checked equal by
  `tests/test_astro_box.py`): MAGIC 'ASTR', VERSION, BEAT (glass); SEQ (ZIGGY: the doorbell, last);
  TAKEN, DONE, ARM_NS, RET (glass); COUNT, MEM_OFF, MEM_SIZE (ZIGGY); descriptors from word 16. Every
  word has one writer.
- **ZIGGY's side** (`cycles/bastro_post.h`, wrapped around the machine's export as `hwBlit` is): copies
  only the words glass reads (a scalar op: OP and S0-S2; an array op: OP, N..C, S0), writes SEQ. SEQ is
  an IO store, so the SoC holds it until every posted DDR store has landed (`soc/zm_io_fence.py`): the
  cart's arrays are in DDR when the ARM sees SEQ. Waits TAKEN (50 ms), then DONE (10 s), copies STATUS
  and R back, drops the D-cache after an array op (the ARM wrote DDR behind it).
- **glass's side** (`glass/src/astro.zig`, `astro_box.zig`): a thread pinned to core 1
  (`sched_setaffinity`) spins on SEQ while requests come and naps 1 ms after 2 s idle (BEAT counts the
  naps). Each array is checked against the cart's memory and the memory against the DDR window before a
  word is read (the cart is not trusted), staged from DDR into a cached 8 MB mirror, computed, staged
  back. `dsb` before DONE.
- **When nobody answers**: no STATUS.ASTRO, no MAGIC, or not TAKEN in 50 ms: the request is withdrawn
  (SEQ = 0; glass re-reads SEQ after TAKEN and never serves a withdrawn one), the machine's own code runs
  on ZIGGY, and the mailbox is not tried again until BEAT moves. Taken but not DONE in 10 s: ST_TIMEOUT,
  never a local rerun (an in-place AXPY or GEFA would be applied twice).
- **Jitter**: the worker is an ordinary Linux thread. For a quiet core, boot the kernel with
  `isolcpus=1 nohz_full=1 rcu_nocbs=1` (U-Boot `bootargs`, the lead's change); glass still pins itself
  there, and only it runs there. Without it, a request can wait a scheduler tick (~10 ms) when another
  thread holds core 1: that is the p99 row `glass astro-bench` prints.
- **IRQ**: not built. A cart IRQ on DONE (an async `hwAstro` that returns at once, the cart polling
  STATUS or taking an interrupt) is the obvious next step once the round trip is measured.

## 5. Strengths and drawbacks

Board figures are *est.* until measured (§6). ZIGGY at 100 MHz; GP0 single-beat access ~100-200 ns
*est.*; uncached DDR from the ARM ~100-200 ns a word *est.*

| | ZIGGY f32 | ZIGGY soft f64 | ASTROLABE (board) | ASTROLABE (browser) |
|---|---|---|---|---|
| precision | f32 (24-bit) | f64, IEEE | f64, IEEE, the same bits as the soft f64 | same bits |
| add / mul | 1-10 cycles (FPU) | ~50-150 cycles *est.* | ~150-300 cycles a call *est.* (the round trip): **loses** | free |
| div / sqrt | ~10-30 (FPU) | ~560 / ~1,400 (sim, below) | the round trip: about even | free |
| sin / exp / pow | (sinf: soft) | sin ~7,000 (sim, below) | the round trip: **wins ~10-20x** *est.* | free |
| 48 scalar ops a call | | | ~8 GP0 words each: ~1.2 µs/op *est.*: wins only for libm | |
| 4096-element sin | ~4 ms | ~150 ms *est.* | ~2.5 ms *est.* (DDR staging dominates) | |
| LINPACK 100 (0.69 MFLOP) | | ~0.5-1 s *est.* | ~15-20 ms *est.* | |
| latency jitter | none | none | Linux: a tick when core 1 is busy; isolcpus fixes it | none |
| cost | LUTs already spent | none | 1 RAMB36, a handful of LUTs, core 1 at 100 % while busy | none |
| when absent | | | the machine's code on ZIGGY (same bits, soft-float speed) | |

What decides it is the ARM's access cost: every word it reads over GP0 (the mailbox) or from uncached
DDR (the arrays) is a full bus round trip. If `astro-bench` shows those at the slow end, the next lever
is a cached view of the cart's arrays (a kernel driver with cache maintenance, or the coherent ACP port),
not more mailbox.

**Measured in the board SoC's simulation** (9 Nov, `hp_sim --sound-cpu --astro` on omarchy, the default
`I16w2D4Seal` core: no f32 FPU, so the cart's f32 is soft here too; ASTRO BENCH, 6 frames, one job a
frame; no ARM behind the mailbox, so MAGIC reads 0 and every call is ZIGGY's fallback, which is the
soft-f64 baseline). The cart's ZIGGY cycles per frame (`ZM VS`, field 2):

| frame (job) | what runs | ZIGGY cycles |
|---|---|---|
| 1 roundtrip | 256 hwAstro NOP calls (+ the screen's title) | 0.46 M: at most ~1.8 k a fallback call |
| 2 add | 1,024 fallback ADDs (256 calls of 1, 16 of 48), 4,096 cart f64 adds, 4,096 f32 | 14.4 M |
| 3 mul | the same with MUL | 15.2 M |
| 4 div | DIV | 17.3 M (+2.9 M over add: ~560 cycles a soft divide) |
| 5 sqrt | SQRT | 21.7 M (+7.3 M: ~1,400 cycles a soft sqrt) |
| 6 sin | SIN (~9,300 soft sin/sinf in all) | 65.5 M: ~7 k cycles a soft sin |

`ZM ASTRO 1616 0 0 0 14780048`: 1,616 calls, none served (no ARM), none withdrawn (MAGIC 0: nothing
posted, no 50 ms wait), 14.8 M cycles inside hwAstro (the machine's kernels as ZIGGY's soft f64). So a
soft-f64 `sin` is ~7,000 ZIGGY cycles (70 µs at 100 MHz): the round trip has a lot of room against
libm, little against add/mul. (Frame 6's sequencer field, 80 M, is the sim hashing that frame.)
The PFB-hash verdict of `hp_sim_run` cannot pass for this cart (it draws clock-dependent numbers), so
the UART is the result.

## 6. How to measure (the lead, on the board)

1. `glass astro-bench` (any bitstream, beside a running glass): ns per GP0 register read/write, mailbox
   read/write (0 on a bitstream without it: the page reads 0), uncached DDR read, f64 add/div/sqrt/sin
   on the A9, as min / median / p99 / max.
2. The ASTROLABE bitstream + the new glass + `KESTREL/system.rv32` (table 1.18) + the ASTRO BENCH cart:
   the screen shows `roundtrip ns=… cycles=min/med/p99/max served=n/n`, each op's
   `astro1 astro48 soft64 f32` ns per op, LINPACK KFLOPS soft vs astro, the 4096 sin batch.
   `served` = the ARM answered (0 = fallback). The same cart on the old bitstream is the soft baseline.

## 7. Tests

- `machine/astro_test.zig` (native, gated): every op, FMA's single rounding, f32 out, GEMV with lda,
  LINPACK 100 to ones, every refusal writes nothing, a batch reports the first failure.
- `fpga/tests/test_rtl_glass.py` `zm_astro_top` (CXXRTL): both ports, byte lanes, no aliasing, a read
  meeting a write, a torn-word check, a one-clock ack; 9 mutants (`ZM_RTL_BREAK=1`).
- `fpga/tests/test_astro_box.py` (gated): the four copies of the layout agree; ZIGGY's protocol against a
  scripted glass (served, words per op class, no worker, withdrawn, dead until BEAT, TIMEOUT never rerun,
  a late worker serves nothing); 10 mutants.
- `fpga/glass` `zig build test`: the server (served once, staged AXPY, refusals, withdrawn).
- `apps/astro_bench_headless.mjs` (gated, `--break result|batch|clock`): the bench cart in the page's
  binding: 0 ulp, LINPACK same bits, reference bits vs JavaScript, no clock, rerun, screen.
