# Third-party cores

Git submodules, shallow and pinned to a commit (`git submodule status`). Fetch
them with `make setup`. They keep their own licences; nothing here is copied
into ZigMachine's own sources.

| Core | What it is for | Licence | Measured (Yosys, xc7) |
|---|---|---|---|
| [`jt49`](https://github.com/jotego/jt49) | The YM2149. Used as is. | GPL-3.0 | 286 LUT, 291 FF |
| [`VexRiscv`](https://github.com/SpinalHDL/VexRiscv) | The cart CPU (Scala source). The netlists LiteX builds come from `pythondata-cpu-vexriscv`. | MIT | `standard`: 2,019 LUT, 9 BRAM, 4 DSP |
| [`neorv32`](https://github.com/stnolting/neorv32) | The alternative cart CPU, with PMP (the execute-only ROM rule). | BSD-3-Clause | not yet |
| [`hdmi`](https://github.com/hdl-util/hdmi) | HDMI with audio data islands: sound over the same cable. | MIT or Apache-2.0 | its `real` parameters defeat Yosys |
| [`fx68k`](https://github.com/ijor/fx68k) | A cycle-exact 68000: the optional SNDH coprocessor. | GPL-3.0 | 3,357 LUT (19 % of a 7010) |
| [`AtariST_MiSTer`](https://github.com/MiSTer-devel/AtariST_MiSTer) | **Reference only**: the ST's shifter and MMU (`rtl/gstmcu`), blitter (`stBlitter.sv`), YM (`ym2149.sv`), MFP. Read for how the ST did it. Do not instantiate. | GPL-3.0 (no licence file at the repo root) | |

## Licence note

ZigMachine has no licence file yet, and the earlier rule still holds: GPL code
is not absorbed into the project's own sources. The GPL cores (`jt49`, `fx68k`)
are used as separate modules. A **bitstream** that contains them is a combined
work under the GPL, though. That is fine for a personal board, but it has to be
decided before any bitstream is distributed. If it matters, the permissive
alternative to `jt49` is to write the YM in-house from `machine/audio/ym.zig`,
which is the reference anyway.
