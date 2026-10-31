# ZIGGY ISA extensions: what would pay (study, 2026-10-31)

Question (Matt): which RISC-V extensions and CUSTOM instructions would make ZIGGY (VexRiscv rv32imf,
I$ 16 KB 2-way, D$ 4 KB direct-mapped, posted stores, 100 MHz, the SoC at ~89 % LUT) better at what
the shelf's carts actually do? Budget bar, from the last LUT decision (F3_ROW_ENCODING.md, 2026-10-24):
~0.03 Mc a frame for 150-250 LUT at 89 % was "not now".

## Verdict

1. **No integer ISA change moves a cart across the 60 fps knee today.** The six carts estimated over
   1.75 Mc are bound elsewhere: replicants (cart 0.08 Mc), tsl_hybridglenz (0.01), deltaforce2 (0.26)
   are FRESCO/CHISEL-bound; raytrace_f32, polkadots(_f32) are f32/FPU and soft-float bound. Everything
   below is HEADROOM, not fps.
2. **Standard extensions (Zba/Zbb/Zbs, Zicond, C, P) do not pay.** All of Zba+Zbb+Zbs together save
   0.37 Mc summed over 109 carts: median 0.001 Mc a cart, best gem 0.046. GCC 13 emitted 46 B-ext
   instructions in leonard_spirit's whole cart (code 18,208 -> 18,104 B). C shrinks code 23 % but no
   cart's working set reaches the I$ (max 13 KB of 16).
3. **One custom instruction has evidence: planar->chunky (`zm.p2c`).** The ST-screen ports convert a
   whole planar screen every frame through nibble/byte tables: rick_dangerous 0.60 Mc, rno_natrium
   0.46, naos_nitrowave 0.08 (rno_sodium, swedish_newyear, snyd_90, lockbuster2 carry planar
   conversion code too, not hot in the census window).
   A 4-pixel permutation op saves ~0.35-0.48 Mc on each of the two big ones, for an estimated
   60-120 LUT. Both already run 60 fps on the board, so it is headroom, and a software fix (convert
   only the changed 16-px groups, or a merge-transpose p2c) gets part of it at 0 LUT.
4. **The bigger lever for the same carts is not the CPU:** a FRESCO planar (ST shifter) plane mode
   would delete the conversion AND halve the plane's row reads. That belongs to the FRESCO study.
5. **Mode 7 (coordinator's question):** a CHISEL affine texture-walk op is worth more than any CPU
   op for rotozooms/floors (anima roto 0.47 Mc, cuddly_starwars 0.34), ~300-500 LUT + perhaps a BRAM.
   The copper's REG cannot drive CHISEL today (below).

**Recommendation:** build nothing in the CPU now. If Matt wants one ISA prototype for the "oldskool
SoC" story, `zm.p2c` is the one: smallest, pixel-exact by construction, real users. Its LUT number
comes from a synth-only OOC run (staging below), not from a board bitstream.

## Ranking (value per LUT)

| # | item | evidence (Mc/frame saved, est.) | LUT (est.) | toolchain path | verdict |
|---|---|---|---|---|---|
| 1 | custom `zm.p2c` (planar->chunky, 4 px) | rick 0.48, rno_natrium 0.36, naos ~0.06 | 60-120 | span import, `#define` to inline asm on the board | prototype candidate |
| 2 | CHISEL AFFINE op (+ row table) | anima roto 0.47 -> ~0.15; cuddly 0.34 -> ~0.1 | 300-500, 0-1 BRAM36 | new hwBlit op, same import | worth a design note |
| 3 | CHISEL map-gather op (tunnel) | anima tunnel 0.59 -> ~0.15 | +100-150 on #2 | same | with #2 |
| 4 | Zba (sh1/2/3add) | 0.152 shelf-wide, best rick 0.028 | 40-60 + decode | `-march=..._zba`, GCC emits it from wasm2c C | no |
| 5 | Zbb subset (min/max/zext.h/sext/andn/clz) | 0.20 shelf-wide, best gem 0.046 | 150-450 | `_zbb` | no |
| 6 | Zbs | 0.024 shelf-wide | 60-80 | `_zbs` | no |
| 7 | C (compressed) | 0 Mc today (no cart near 16 KB); -23 % code | 250-350 + fetch-path timing | `rv32imfc` | no; revisit if a cart overflows the I$ |
| 8 | Zicond | 0.11 shelf-wide at best (mispredicts only) | 50-100 | GCC 13 does not emit it (tested) | no |
| 9 | Q16 MULSH, MAC | 3 matches shelf-wide | 50-100 | intrinsic only | no |
| 10 | P subset (packed 8/16), saturating add, fixtrig, reciprocal | see "Rejected" | 200-800 | no GCC 13 rv32 support | no |

## Method

- **Dynamic census** (`apps/perf/isa_census.mjs`, new): runs each cart instrumented exactly as
  frame_cost does (counter per straight-line segment, ROM included), then matches every executed wasm
  op against peephole patterns using the operand producers of `apps/perf/flow.mjs` (e.g. an `i32.add`
  or a load/store address fed by `i32.shl 1|2|3` is a Zba shift-add; a `select` on a compare of its own
  operands is a min/max). Matches x segment counts = matches a frame; x the rv32 instructions saved x
  CPI 0.86 = Mc. Window: warmup 120, 30 frames, one phase per cart (anima also measured at frames
  2300 and 3200 for its tunnel and roto parts with frame_cost). It is an estimate, like frame_cost.
- **Static compile**: leonard_spirit's board cart.c (wasm2c, split.mk's CART_CFLAGS) with GCC 13.2
  `-march=rv32imf`, `rv32imf_zba_zbb_zbs`, `rv32imfc`: code 18,208 / 18,104 / 13,978 B.
- **Hot loops** read from `frame_cost` hot regions and `wasm-objdump` of the same docs/ wasm (cmp'd
  identical to the board-lean tree whose wasm2c C was read).
- Not modelled: branch mispredicts, and the firmware's share of the I$ (vseq/bmain/trap code runs every
  frame next to the cart; codeKB counts cart + ROM only).

## Standard extensions

| pattern | executions a frame, shelf | top carts | save/op |
|---|---:|---|---:|
| Zba shift-add (adds + load/store addresses) | 181,076 | rick 32 K, rno_natrium 27 K, swedish 14 K | 1 |
| Zbb zext.h (`& 0xffff`) | 123,160 | union_intro 20 K, gem 16 K, maxi 12 K | 1 |
| Zbb sext.b/h | 30,896 | gem 23 K | 1 |
| Zbb andn/orn | 18,387 | gem 7 K | 1 |
| Zbb min/max, clamp | 12,881 | union_tnt3 2.3 K, polkadots 2.8 K | 2 |
| Zbb clz/ctz/cpop (libgcc calls) | 3,455 | union_l16 2.8 K | ~12 |
| Zbb rotate | 369 | | 2 |
| Zbs bit set/clear/extract | 32,465 | gem 7 K, union_demo 6 K | 1 |
| other `select` (Zicond) | 281,947 | raytrace_f32 68 K | 0-0.5 |
| i32 divide, non-constant | 5,379 | raytrace_f32 1.5 K, polkadots 1.2 K | (36 cyc each, 0.19 Mc total) |

Against 27.5 M wasm ops a frame shelf-wide, the whole B family is ~1.5 %. The two cheap B items with
real counts (union_l16's clz calls, bubblebobble's per-pixel 64-bit divide below) are software fixes.

- **VexRiscv**: this checkout (fpga/third_party/VexRiscv) has no Zb* plugins; each would be a custom
  plugin in the `SimdAddPlugin` / CfuPlugin style (decode mask + execute-stage result), or a newer
  upstream. C is `compressedGen = true` in IBusCachedPlugin: an RVC decoder and a realigning fetch, on
  the fetch->decode cone that TIMING_FABLE.md already calls critical.
- **Toolchain**: GCC 13.2 accepts `rv32imf_zba_zbb_zbs` and emits sh2add/minu/zext.h/bseti from
  wasm2c's C with no source change (lean carts link only libgcc, so no multilib issue). It accepts
  `_zicond` but emits `beq/mv` for a select (GCC 14 is needed). No GCC 13 rv32 P support.
- **C and the I$**: the bench's `ic.over.24K` (3.91 cycles an instruction vs 1.01) is a real cliff, but
  the largest working set is union_tnt3's 13 KB (+ firmware). C buys margin, not speed, today.
- **Q16.16 multiply-shift**: wasm i64 multiplies are 15.6 K a frame shelf-wide and feed `i64.add`
  (dot-product accumulation), not a shift: only 3 sites match `(i64)a*b >> k`. No case.

## Custom instructions

**How a cart reaches one** (this decides the ranking): a wasm import is a call through env in wasm2c,
tens of cycles, so a per-pixel import loses everything. Two workable shapes:
- *Inline on the board*: wasm2c calls an import as `w2c_env_NAME(instance->w2c_env_instance, ...)`
  after `zm_variant.h` is spliced in, so a `#define w2c_env_zmP2c(env, a, b, k) zm_p2c(a, b, k)` there
  turns it into one `.insn r CUSTOM_0` with no call. The browser and node implement the same import
  (in rom.wasm, wasm-to-wasm: cheap); disk_check.mjs's hostEnv must list it.
- *Span-granular*: `zg.p2cLine(src, dst, groups)` as the import, a C loop with the instruction on the
  board, the current Zig on the browser. Fewer ABI entries; one call a line is noise.
Either way the browser runs the existing Zig code, so pixels are identical by construction; a test
pins the instruction's semantics against `naos_nitrowave/planar.zig groupToChunky` (exhaustive per
byte lane), plus an RTL testbench and a break test.

**`zm.p2c rd, rs1, rs2, k`** (custom-0, funct3 = k in 0..3): rs1/rs2 = the 8 bytes of one ST group as
loaded by two `lw` (planes 0,1 / 2,3, big-endian words); rd = chunky pixels 4k..4k+3, pixel 0 the
leftmost (bit 15), plane p as bit p. Pure wiring: each output bit is a 4:1 mux on k (one LUT6), 16
live bits, plus a result-mux leg and decode: ~60-120 LUT, no timing risk beyond the writeback mux.
Per 16 px: 2 lw + 4 p2c + 4 sw + loop ~ 25-30 cycles with the source misses, against 145 (rick: 8 px
an iteration at 72.7 cycles, four i64 table loads each) and 129 (rno_natrium). The current loops are
partly D$-bound (tables against the streaming source; naos's comment: the 8 KB u64 table "did not fit"),
which the op removes with the tables.

**Other hot loops read** (top loop of each heavy CPU cart):

| cart | loop | Mc | shape | ISA help? |
|---|---|---:|---|---|
| bubblebobble f154 | scaled sprite | 0.51 | `__udivdi3` per pixel (u = x*w/W in u64) | no: DDA step in software (BAD_PATTERNS div_loop) |
| union_demo f92 | keyed 4-px merge | 0.36 | byte == key select per pixel, masks | marginal (CHISEL keyed BLIT exists) |
| music f60 | table-addressed byte scatter | 0.31 | load8/store8 via offset table | no |
| skystrike f46, snyd_90, tnt3, swedish | compare-before-store | 0.2-0.4 | word compares | no (memory-bound) |
| anima f56 | roto / tunnel | 0.47 / 0.59 | fixed-point u,v -> texel byte | CHISEL op (below) |
| cuddly_starwars f46 | perspective rows | 0.34 | 24-bit fraction DDA | CHISEL op (below) |

**Rejected**: fixtrig unit (a sine is one table `lw` already); reciprocal/divide step (floors divide
once per ROW: 200 x 36 cycles); saturating colour add (fades are palette writes, ~free); glenz OR-merge
(glenz carts are CHISEL-bound, cart 0.01 Mc); byte gather (one `lbu`; the cost is the address math
and misses, which the CHISEL op takes whole); packed-pixel P ops (no GCC path; would need cart rewrites
for loops that are store- or miss-bound).

## Mode 7: CHISEL affine walk vs a CPU reciprocal

**Copper REG cannot drive CHISEL today.** COPPER_LIST.md (HW 1.9.0): REG writes a u16 register of THE
SAME PLANE and only HSCROLL+2p is accepted (zm_video_copper.v: `hs_we`); other offsets are refused and
counted. And it runs inside FRESCO's pass, after the cart's frame, when CHISEL has finished: the
board's frame is cart (CPU + CHISEL) then compositing, serially (cycles/bmain.c). An HDMA-style
per-line rewrite of CHISEL parameters would need CHISEL raced against the beam: a different machine.

**What fits the machine: an AFFINE op with a row table.** Per destination pixel u += du_x, v += dv_x;
per row (u0, v0, du_x, dv_x) either stepped (rotozoom: + du_y, dv_y) or fetched from a 16-byte-a-row
table in cart RAM (perspective floor, star-wars text: the HDMA list, read by CHISEL itself). Texel
address = A_base + ((v >> 16) & mask_v) * stride + ((u >> 16) & mask_u), power-of-two texture so no
multiply. It is a new sequencer beside zm_blit_blit (100 LUT in the 10-10 place report) feeding the
existing pixel unit (keys, minterms, clipping and writes unchanged); zm_blit_px already keeps 2^5
reads in flight, so random texel reads pipeline. Estimate: sequencer + 2 accumulators + wrap 150-250
LUT, registers 100-150, row-table fetch ~100: **300-500 LUT**; a texture-local BRAM (+1 BRAM36 for
64x64) only if DDR random reads prove slower than ~3 clocks a pixel. A tunnel needs a sibling MAP mode
(texel = tex[(map[i] + offset) & mask], map in cart RAM): +100-150 LUT.

**Who uses it, CPU saved a frame** (the CPU spins on BUSY, so CHISEL time is cart time; 1.5-3 clocks
a pixel assumed, 800 a call): anima roto 0.47 -> ~0.15, anima tunnel 0.59 -> ~0.15 (MAP mode),
cuddly_starwars 0.34 -> ~0.1 (row table), rno_natrium's tunnel part (not in the census window).
A per-row op without a table costs 200 x 800 = 0.16 Mc of starts alone: the table is the point.
**The CPU alternative** (a reciprocal instruction) saves ~7 Kc a frame on a floor: nothing. CHISEL is
already ~2,200-3,700 LUT (20 % of the die), so this competes with the LUT diet; worth a design note
when a new rotozoom/floor port wants more than 60 fps headroom, not before.

## Staging (only if the lead wants the zm.p2c LUT number)

1. `fpga/vexgen`: a `ZmP2cPlugin` (SimdAddPlugin pattern, custom-0 decode) and a `p2c` gen.sh flag;
   regenerate `VexRiscv_I16w2D4SealFpuP2c.v` (needs `ZM_VEXGEN=1 tools/setup.sh` in the worktree).
2. Synth-only OOC of the core alone, both netlists, under the vivado lock (fpga/tools/vivado_ooc.sh):
   the LUT delta and the execute->writeback slack. No bitstream.
3. The native bench cannot run a new opcode until the Verilated SoC is rebuilt with that core (a
   heavy hp_sim build); the cycle estimate above is from the loop shapes, not a run.
Software first, either way: dirty-group p2c in rick_dangerous/rno_natrium costs 0 LUT.

## Reproduce

```sh
node apps/perf/isa_census.mjs --all --json > census.jsonl      # ~4 min, serial, one phase per cart
node apps/perf/isa_census.mjs docs/demo-rick_dangerous.wasm     # one cart: Mc saved by pattern
node apps/frame_cost.mjs docs/demo-anima.wasm --warmup 3200 --frames 20   # anima's roto part
```
