# `fpga/host/`: the native host (plan step 0b-i)

ZigMachine's wasm modules (`machine-video.wasm`, `rom.wasm` and one cart) are
translated to C by wasm2c and linked into one native program. That program
drives them exactly as `apps/scene_hash.mjs` drives the wasm, and it prints the
same JSON. Same JSON means same pixels, so the translated machine is proven
against the wasm machine before any of it runs on a RISC-V core.

```sh
make -C fpga host CART=stniccc                  # -> fpga/build/host/stniccc/host
fpga/build/host/stniccc/host docs/demo-stniccc.wasm 1200 10 > native.json
node apps/scene_hash.mjs docs/demo-stniccc.wasm 1200 10 > wasm.json
node apps/scene_hash.mjs --compare wasm.json native.json
make -C fpga host-check                         # every cart; tools/host_check.sh
make -C fpga host CART=stniccc HOST_WALLCLOCK=-DHOST_WALLCLOCK   # + ms/frame on stderr
```

The arguments are scene_hash.mjs's: `<cart> [frames=1200] [every=10] [--call F:export:args]`.
The cart is linked in, so `<cart>` is only echoed into the JSON. That keeps the
two outputs identical byte for byte, so `cmp` is enough to compare them.

## The call sequence (scene_hash.mjs, reproduced in `boot.c` / `main.c`)

1. One memory, `initial = maximum = SHARED_PAGES` (112 pages = 7 MiB, from
   `machine/sdk/memmap.zig` via `gen/memmap.py`). Every module imports it as
   `env.memory`, and none of them grows it.
2. Instantiate `machine-video` (env: `memory`, `hblDispatch -> cart.hblDispatch`).
   Instantiation runs its data segments into the shared memory.
3. Instantiate `rom` (env: `memory`, `hwVideoBase`, `hwBlit`, both from the machine).
4. `machine.hwSetRomHigh(romRam(rom.wasm).high ?? 0)`.
5. Instantiate the cart. Its env holds: the machine's `hwVideoBase hwBlit
   hwRam{Base,Top,Size,Used,Free,Alloc,Mark,Release,AllocFailures}
   hwRomRam{Base,Top,Size,Used,Free}`, then every rom export spread over that
   (`...rom`, so rom wins a name clash). **Every other import is a no-op**.
6. `machine.hwSetCartHigh(cartRam(cart.wasm).high ?? 0)`, `machine.hwInit()`,
   `cart.boot()`, `cart.skipBoot()`.
7. For `f = 1..frames`, first run any `--call` due at `f`. Then:
   `hwClear()`, `cart.frame(16.6)` (an f32), and for each `p < hwPlanesNumber()`
   either hash `"off<p>"` if `!cart.isPlaneEnabled(p)`, or `hwRenderPlane(p)` and
   hash the `hwPhysWidth*hwPhysHeight*4` bytes at `hwPhysicalPtr()`. Every
   enabled plane is rendered EVERY frame, because HBL handlers (`hblDispatch`)
   only run inside `hwRenderPlane`. The hash is only kept every `every` frames.
8. Each sample is `sha256(those bytes)` as hex, and `total = sha256(concatenated
   hex digests)`. The JSON is printed, then the exit is 1 if
   `hwRamAllocFailures() != 0`.

`.high` is `cartHighWater` in `docs/wasm_hiwater.js`: the max of the mutable i32
globals' initial values (`__stack_pointer`) and the end of the last active data
segment. `tools/wasm_info.py` ports it with the JS's 32-bit LEB arithmetic, and
`tests/test_host_gen.py` checks it against the JS on every module.

## How the imports are served

wasm2c names every import `w2c_env_<name>(struct w2c_env*, ...)`, whichever
module imports it. So `struct w2c_env` (in `host.h`) is the whole host: the
memory plus the three instances. One definition of each `w2c_env_*` serves all
three modules. `tools/host_gen.py` writes those definitions per cart into
`build/host/<tag>/env.c`, from the wasm2c headers:

| Import | Served by | Why |
|---|---|---|
| `memory` | `boot.c`: the one shared memory | `env.memory` |
| `hblDispatch` (machine) | `cart.hblDispatch` | scene_hash's closure |
| rom export names (`gui*`, `desk*`, `dialog*`, `fileSel*`, `romScratch*`, `romInstallPalettePlane`, ...) | rom | `...rom` |
| the 16 machine names above | machine | the explicit list |
| anything else (`jsConsoleLog*`, `consoleLogJS`, `diskReadBlock`, `hostAudio*`, `machine*` audio) | **stub** | scene_hash's `noop` |

The stubs do what `() => {}` does across the JS-to-wasm boundary: `undefined`
becomes 0 for an i32 and NaN for a float, and an i64 result would throw a
TypeError (here it traps). So `diskReadBlock` returns 0 in both hosts: no disk,
no console, no audio. That is faithful to the oracle, not to the browser. A
screen that streams from disk (stniccc) renders the same frame in both.

The generator also refuses what the JS refuses. A module whose `env.memory`
limits do not admit 112 pages (`demo-audio.wasm`, max 48: a LinkError in node)
gets no host. A signature mismatch between an import and the export serving it
fails the build.

`--call F:name:a,b` invokes any cart export whose parameters a JS Number can
feed. Each argument goes through ToInt32 for an i32 and `(float)` (= `Math.fround`)
for an f32. A missing argument converts as `undefined` does.

## Portability (for step 0b-ii)

- **Bounds-checked memory, no mmap:** `-DWASM_RT_USE_MMAP=0
  -DWASM_RT_MEMCHECK_BOUNDS_CHECK=1`. The 7 MiB memory is `calloc`'d, and there
  are no guard pages or signal handlers. Stack exhaustion is a depth counter
  (`WASM_RT_MAX_CALL_STACK_DEPTH=10000`, deep enough for V8's own limit to bite first).
- **`-ffp-contract=off`:** wasm never fuses `a*b+c`. An FPU with `fmadd.s` (rv32 F)
  would fuse it under clang's default and round differently.
- Plain C11 plus `_POSIX_C_SOURCE`, which the stock wasm2c runtime needs for
  `sigsetjmp`. Wall-clock timing exists only under `-DHOST_WALLCLOCK`.
- Every object (runtime, machine, rom, cart, host) compiles for
  `riscv32 -mcpu=generic_rv32+m+f` with `zig cc` unchanged. Linking for the sim
  needs a bare-metal libc (picolibc, which LiteX ships). Zig's musl cannot link
  rv32 without A and D. See the step 0b-ii notes in the top-level report and in
  `docs/ZIGMACHINE_IN_FPGA.md`.

## Files

| File | What |
|---|---|
| `host.h` | `struct w2c_env` (memory + instances), the generated constants, `host_export` |
| `boot.c/.h` | the instantiation order, `w2c_env_memory`, ToInt32, `--call` dispatch |
| `main.c` | arguments, the frame loop, the JSON, trap reporting |
| `sha256.c/.h` | FIPS 180-4, streaming, no platform calls |
| `../tools/host_gen.py` | per-cart `env.c`: import forwarders/stubs, export table, high-waters |
| `../tools/wasm_info.py` | `cartHighWater` port, `env.memory` limits |
| `../tools/host_check.sh` | runs both hosts on every cart and writes `build/host/check/report.txt` |
