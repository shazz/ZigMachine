# KESTREL bench reports

These are measured costs of ZIGGY, CHISEL and FRESCO on the real board. They come from the native bench
cart (`fpga/cycles/native/bench/`, built with `make native-cart NAME=bench`), not from models. Each run
appends a section here and its raw log goes in `fpga/bench_results/`.

## Method

- **Clock:** ZMCycles at `0xf0002000`, read directly by the cart: 100 MHz, the sys_clk. ZIGGY runs with
  interrupts off, so nothing preempts a test.
- **Repeats:** each test body runs 7 times between two counter reads. The table gives the **min**, and the
  median is in the raw log. The empty-body cost (`calib.empty`, 14 cycles) is subtracted.
- **Bus counters:** `dwait` and `dwr` (data-bus wait cycles, data-bus writes) come from the same window.
- **One test a frame.** The frame tests (`fr.*`) leave the frame right after a VBL, so their time is pure
  system and compositor work.
- **Output:** results go to an in-cart log of `ZMBENCH name= size= cyc= med= ops= dwait= dwr=` lines and to
  the screen. `fpga/tools/bench_collect.py [--load demo-bench.zmd]` reads the log over the serial console
  with `devmem` and writes `.txt` + `.csv` (cycles/op, MB/s).
- **Re-run on a new bitstream or system image:** upload `zigmachine/demo-bench.zmd`, `killall glass`, then
  `fpga/.venv/bin/python fpga/tools/bench_collect.py --load demo-bench.zmd --out <dir>`.

---

## 2026-10-18 — board v6 FPU bitstream, `posted=0` (baseline)

- **Hardware:** bitstream md5 `3a734631…` (perf/lut-diet tip): 14,888 LUT (84.6 %), sys 100 MHz,
  comp 125 MHz, ZIGGY rv32imf with the FPU, HP0 stores **not posted**.
- **System image:** system.rv32 table 1.1, from before perf/chisel-burst, so it still has the old hwBlit
  overhead.
- **Raw log:** `fpga/bench_results/2026-10-18_v6fpu_posted0.{txt,csv}` (113 results).

### Headline findings

1. **Every store costs 18 cycles**: sb, sh or sw; sequential, the same address or strided; cart RAM,
   VRAM, palette or registers. So byte stores move 5.6 MB/s and word stores 22 MB/s.
2. **Work between stores is free.** 4 or 16 ALU ops between two stores cost nothing (`st.alu16` =
   `st.alu0` = 18). ZIGGY overlaps one store with later work. What limits it is store **throughput**:
   one write in flight on HP0. Posting with several writes in flight (`soc/zm_hp_posted.py` keeps up to
   8) should bring a store close to ~3 cycles.
3. **memset is no faster than a word loop.** The system memset and a hand-unrolled word loop both run at
   4.5 cycles/byte (18 a word). memcpy runs at 6.1 cycles/byte. The DDR write path is the limit.
4. **CHISEL is fast, but its call was expensive.** Fill runs at 1.03 cycles/byte and copy at 1.30 at
   64 KB, 4.4–4.7× the CPU. A call through the system cost ~1,100 cycles, against 543 poking CHISEL
   directly, so CHISEL only pays off above ~256 B–1 KB, and an 8x8 blit costs ~1,220 cycles.
   perf/chisel-burst halves the call overhead (predicted ~910 for 8x8); re-measure.
5. **Misaligned lw/sw/sh trap: ~693 cycles each**, against 11 for the same access as byte loads (63×).
   This was the hidden cost of ics (~12.5 K traps a frame) and naos_nitrowave (~22.9 K).
6. **Compositing:** an empty frame costs 0.157 Mc. Each enabled **static** plane adds ~0.33 Mc (the
   dirty-line planner skips its lines). Each **fully redrawn** plane adds ~1.17 Mc, about 4.2 K cycles
   per composited line-pass. At 30 fps a cart can afford about 2 fully redrawn planes.
7. **Reads are cheap:** a D$ hit costs ~1.7 cycles, a line miss ~48 and a CSR read 5.4. vseq's status
   polls themselves cost almost nothing; the time is the pass.
8. **Float:** an f32 add or mul costs ~9–10 cycles in a dependent chain and a divide 21, on the FPU.
   f64 is soft-float at 207 / 417 / 702 cycles (add/mul/div), so avoid it per frame. An i32 divide
   costs 36.

### Stores (`kern_store.S`)

| Test | Bytes | cycles/op | MB/s |
|---|---:|---:|---:|
| st.sb.1K / 16K / 256K | 1 K–256 K | 18.00 | 5.6 |
| st.sh.1K / 16K / 256K | 1 K–256 K | 18.00 | 11.1 |
| st.sw.1K / 16K / 256K | 1 K–256 K | 18.00 | 22.2 |
| st.sw.same (one address) | 16 K | 18.00 | 22.2 |
| st.sw.str32 / str64 (stride) | 16 K | 18.00 | 22.2 |
| st.alu0 / alu4 / alu16 (ALU ops between stores) | 16 K | 18.00 / 18.00 / 18.00 | 22.2 |
| vr.st.sw.16K (VRAM) | 16 K | 18.00 | 22.2 |
| st.pal (palette) / st.reg.bg (register) | 16 K | 18.00 | 22.2 |

### Loads and read-after-write (`kern_load.S`)

| Test | cycles/op | Note |
|---|---:|---|
| ld.hit.2K | 1.74 | D$ hit |
| ld.seq.64K | 7.19 per word | streaming: one miss per line |
| ld.miss.64K | 48.26 per line | D$ line miss |
| ld.chase.hit / ld.chase.miss | 3.15 / 49.17 | dependent load |
| raw.hit / raw.miss | 18.25 / 66.06 | a store, then a load of the same word |
| vr.ld.miss.64K | 48.26 | VRAM reads cost the same as cart RAM |

### memset / memcpy (cycles per byte)

| Size | ms.lib | ms.word | ms.chisel | ms.raw (CHISEL direct) | mc.lib | mc.word | mc.chisel |
|---|---:|---:|---:|---:|---:|---:|---:|
| 64 B | 4.97 | 4.53 | 17.27 | 8.86 | 5.20 | 4.70 | 18.91 |
| 1 KB | 4.53 | 4.50 | 2.39 | 1.49 | 4.77 | 4.56 | 2.68 |
| 8 KB | 4.50 | 4.50 | 1.21 | 1.06 | 6.14 | 6.24 | 1.46 |
| 32 KB | 4.50 | 4.50 | 1.06 | 1.02 | 6.11 | 6.23 | 1.33 |
| 64 KB | 4.50 | 4.50 | **1.03** | 1.01 | 6.11 | 6.24 | **1.30** |

`lib` is the system's word-wise `zm_string.c`, `word` a hand-unrolled loop, `chisel` the system's
hwBlit, and `raw` CHISEL started and polled by the cart. The `chisel` minus `raw` gap is the system's
per-call overhead.

### CHISEL blits (cycles per blit)

| Test | cycles/blit |
|---|---:|
| ch.fill8.x64 (8x8) | 1,222 |
| ch.raw.fill8.x64 (8x8, direct) | 544 |
| ch.fill16.x16 (16x16) | 1,636 |
| ch.fill64.x1 (64x64) | 6,083 |
| ch.copy8.x64 / copy16.x16 / copy64.x1 | 1,325 / 1,888 / 7,343 |

### Contention (CPU and CHISEL at once)

| Test | cycles/op | vs alone |
|---|---:|---|
| cn.st.alone / cn.st.fill | 18.01 / 18.05 | CPU stores unaffected |
| cn.ld.alone / cn.ld.fill | 48.33 / 53.32 | CPU loads ~10 % slower |
| cn.fill.alone / .st / .ld (64 KB) | 66,016 / 66,042 / 66,065 | CHISEL unaffected |

CHISEL was still busy when the CPU loop ended in 28 of 28 runs, so the overlap was real.

### Registers, compute, I$

| Test | cycles/op |
|---|---:|
| csr.cycles / csr.zmv.status / csr.zmb.status (read) | 5.42 / 5.42 / 4.42 |
| alu.add / alu.mul / alu.div | 1.38 / 3.16 / 36.41 |
| f32.add / f32.mul / f32.div (FPU, dependent chain) | 9.04 / 10.04 / 21.04 |
| f64.add / f64.mul / f64.div (soft-float) | 207 / 417 / 702 |
| ic.fit.8K / ic.over.24K (per instruction) | 1.01 / 3.91 |

### Misaligned access (cycles per access)

| Access | offset 0 | offset 1 / 2 / 3 | as bytes |
|---|---:|---:|---:|
| lw | 1.91 | 693 / 693 / 693 | 10.9 (4 lbu + shifts) |
| sw | 18.1 | 698 / 699 / 699 | 72.1 (4 sb) |
| sh | 18.1 | 662 (offset 1) | 36.1 (2 sb) |

### Frame cost by planes (cycles per frame, nothing drawn)

| Planes | static | fully redrawn |
|---:|---:|---:|
| 0 | 156,626 | — |
| 1 | 485,652 | 674,263 |
| 2 | 817,312 | 1,832,517 |
| 3 | 1,149,849 | 3,007,058 |
| 4 | 1,490,947 | 4,198,660 (2 VBLs) |

The 60 Hz budget is 1.66 Mc a frame and 30 fps is 3.33 Mc.

### What it changed

- **Gemini review §2.1 (posted stores):** confirmed and narrowed. The cost is store throughput, and the
  existing buffer already pipelines up to 8 writes, so enabling it on HP0 is the test
  (perf/ziggy-posted, bitstream pending).
- **Gemini review §2.5 (CHISEL bursts):** not worth it. Fill is limited by 1 px/clock, not by AXI.
  The call overhead was the real cost (perf/chisel-burst).
- **Cost model** (`apps/perf/cost_model.mjs`): the misaligned trap cost is now the measured 693
  cycles. The fitted "27 cycles a store" and "60 a memset word" absorbed other costs; the measured
  values are 18 and 18.
- **Scene rules:** draw with word stores, never bytes. Clear or copy ≥1 KB with CHISEL and anything
  smaller with the CPU. Batch tiny blits. Keep wide accesses aligned. Keep f64 out of the frame. Leave
  a plane static, or disable it, unless it changes.

### Next runs

- The same cart on the **posted=8** bitstream (A/B of findings 1–3).
- The same cart on the system image with **perf/chisel-burst** (finding 4: `ch.fill8.x64`,
  `ms.chisel.64`).
