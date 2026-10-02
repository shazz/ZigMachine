# `fpga/cycles/`: cycles per frame on a real VexRiscv (plan step 0b-ii)

The native host of step 0b-i (`../host/`), rebuilt bare-metal for **rv32im** and
run on the SoC's own cart CPU (VexRiscv `standard`) in a Verilator simulation of
the LiteX SoC. Every frame is timed by a hardware cycle counter and split
between the cart and the machine. The results and the verdict are in
[`../CYCLES.md`](../CYCLES.md).

```sh
make -C fpga cycles CARTS="union_beatdis blitter"     # model + images + sims + report
make -C fpga cycles-fw CART=stniccc VARIANT=aligned   # one image only
tools/cycles_sim.sh build/cycles/aligned/stniccc/main_ram.init /dev/shm/run   # run it by hand
uv run python tools/cycles_report.py                  # re-read the logs, rewrite the report
```

`tools/cycles_run.py` takes `--variants`, `--frames`, `--every` and `--jobs`
(see its `--help`). Logs land in `build/cycles/uart/<variant>/<tag>.txt`, the
oracle JSON in `build/cycles/ref/`, the report in `build/cycles/report.txt`, and
the table in `../CYCLES.md` between its markers.

## The pieces

| Piece | What |
|---|---|
| `../soc/cycles_sim.py` | The SoC with 32 MiB of main RAM, the CPU reset straight into it, no BIOS. The RAM is `$readmemh`'d from the run directory, so one Verilated model runs every image. |
| `../soc/zm_cycles.py` | `ZMCycles`: a free-running cycle counter (the `standard` core has `mcycle` but cannot read it) and counters of the CPU's I-bus and D-bus traffic. One CSR load per counter. |
| `../soc/litex_compat.py` | LiteX 2024.12's memory emitter vs the pinned migen's write-only FIFO ports. Only needed when Verilog is written. |
| `shim/` | **The runtime shim.** The stock wasm2c runtime compiles against picolibc unchanged: `sigsetjmp` becomes `setjmp` (no signals on a bare core), `<pthread.h>` is a no-op mutex (one thread, no shared memory), `<sys/mman.h>` is empty (`WASM_RT_USE_MMAP=0`). |
| `zm_variant.h` | Spliced into each wasm2c output: how wasm memory is accessed (below). |
| `prof.[ch]` | The owner stack: every counter delta goes to CART, MACH, BLIT or IDLE. |
| `fcount.[ch]` | The `float` build: every soft-float routine wrapped (`ld --wrap`), counted and timed per class. |
| `trap.[chS]` | Traps: misaligned loads/stores are emulated and counted, anything else is reported. |
| `board.[ch]`, `main.c` | The UART as picolibc's stdio, the finish register, and the frame loop of `host/main.c` with owners. |

The toolchain is the system `riscv64-unknown-elf-gcc` 13.2 with
`-march=rv32im -mabi=ilp32` and picolibc's multilib, so soft-float is **libgcc's**
soft-fp (same routine names as compiler-rt). `-ffp-contract=off` as in the native
host. The images are 0.3 to 0.5 MB; the wasm memory (7 MiB) is calloc'd.

## Who owns a cycle (the split that matters)

| Owner | What | On the board |
|---|---|---|
| CART | `cart.frame()`, plus every **HBL handler** (`env.hblDispatch`, which `hwRenderPlane` calls once per line) and the rom code they call | the cart CPU: **this is the figure** |
| MACH | `hwClear()` and `hwRenderPlane()` minus the handlers | RTL (video fetch, palettes, compositor) |
| BLIT | `env.hwBlit`, from the cart, the rom or a handler | RTL (the blitter) |
| IDLE | the driver: `isPlaneEnabled`, hashing, printing | nothing |

The owners nest (MACH, then CART inside it for a handler, then BLIT inside that),
so `prof.c` keeps a stack. The hooks are in the generated `env.c`
(`tools/host_gen.py` wraps `hblDispatch` and `hwBlit` in `HOST_SPAN_ENTER/LEAVE`,
empty in the native host). A probe costs a few hundred cycles; `prof_calibrate`
measures what one span costs inside and outside, and the report subtracts it
per span, per counter.

## The builds (variants)

| Variant | Bounds checks | wasm loads/stores | Extra |
|---|---|---|---|
| `stock` | every access | `memcpy` (GCC: 4 x `lbu` + 4 x `sb` + `lw`) | |
| `nobounds` | none: the board's bus window seals the cart | `memcpy` | **the reference figure** |
| `aligned` | none | one `lw`/`sw` | misaligned accesses trap and are emulated |
| `float` | none | `memcpy` | soft-float calls counted and timed |

`aligned` exists because rv32 traps on a misaligned word access, so GCC cannot
turn wasm2c's `memcpy` into a `lw`: every wasm load becomes nine instructions.
Real carts almost always access aligned addresses, so a translation that
trusts alignment and emulates the rare exception (what `trap.c` does, and what
an SBI does) is the realistic board build. `ZM MIS` counts the exceptions.

Every variant prints the scene_hash JSON for its sampled frames, and the report
calls a run `ok` only if those hashes equal BOTH `apps/scene_hash.mjs`'s and the
native host's for the same frames. Hashing runs untimed (IDLE).
