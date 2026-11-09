# Licence notes for apps/c/bench

The BENCH cart (apps/c/scenes/bench.c) runs the same C benchmark sources as the Hatari runs
(prototypes/atari_bench/hatari), so the machines compare like for like. What is here, and under what terms:

| files | origin | licence / terms |
|---|---|---|
| kestrel/* (rt.c, fmath.c, k_*.c, cm_main.c, bench.h, gen.py, build.sh, shim/), scenes/bench.c | own code (this task) | CC0 / public domain |
| kestrel/cm_port/core_portme.{c,h} | written from the EEMBC "barebones" porting template | Apache-2.0, Copyright 2018 EEMBC (header kept in the files) |
| dhry/dhry.h dhry_1.c dhry_2.c README_C | netlib benchmark/dhry-c, Dhrystone 2.1 (R. Weicker, 1988) | free to use and redistribute with the header comments kept; README_C states the rules for publishing results |
| third_party/whetstone.c | netlib benchmark/whetstone.c, C Converted Whetstone Double (Painter Engineering, 1998) | "Permission is granted to use, duplicate, and publish this text and program as long as it includes this entire comment block and limited rights reference" (the block is kept in the file) |
| third_party/linpack.c | netlib benchmark/linpackc.new (B. Toy, W. Menninger, J. Dongarra) | netlib, no restriction stated; public domain in practice |
| third_party/coremark/core_*.c coremark.h | EEMBC CoreMark 1.0, as in czietz/coremark (commit b54680215e981456ad80fb143d096c28c4b03e11) | Apache-2.0 + the EEMBC "CoreMark Acceptable Use Agreement" (third_party/coremark/LICENSE.md). core_*.c stay unmodified; only the porting layer is ours. |

## What is patched, and where

The committed Dhrystone, Whetstone, LINPACK and CoreMark sources are byte-for-byte what was downloaded. Every
edit the slice scheduler needs is made by `kestrel/gen.py` at build time, on a copy (each edit asserts that it
matched exactly once). `build_all.sh` of the Hatari build patches its copies the same way.

## CoreMark: what a score from this cart is, and is not

CoreMark's run rules ask for ONE run of at least 10 s, reported with its own validation line. This cart runs many
short calls of CoreMark's own `main()` (so a frame is never held for long), each with CoreMark's CRC self-check, and
divides the iterations by the summed timed regions. That is the same code timed the same way, for comparing machines;
it is not a reportable "CoreMark score" and must not be quoted as one. The cart labels it "CoreMark (sliced)".

## libm

Double sin/cos/exp/log come from the toolchain's compiler_rt (Zig's std.math, MIT); atan and the whole
single-precision set (`bsinf`...) are `kestrel/fmath.c`, f32 operations only. The Hatari builds used the platform's
libm (newlib/mintlib software float, or the 68881's own instructions), so the transcendental parts of Whetstone are
not identical code across machines.
