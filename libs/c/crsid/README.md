# cRSID: the SID engine the .sid player runs on

Mihaly Horvath's ("Hermit") cRSID: an integer-only Commodore 64 SID emulator with its own 6502, CIAs
and VIC, made for weak CPUs (Rockbox carries it). The .sid player (`libs/zig/players/sid.zig`) uses
its **light engine at 22.05 kHz mono, PSID only**. BARD runs this C natively (`fpga/host/crsid.c`),
the page runs it in `machine-audio.wasm` (`machine/audio/sid.zig`), and `apps/sid_check.mjs` holds the
two to the same samples. Chosen and measured in `fpga/review/SID_BARD_STUDY.md`: 48-60 % of BARD on
PSID tunes; RSID tunes (real C64 programs) cost ~2x BARD and are refused.

## Provenance

| | |
|---|---|
| Upstream | cRSID 1.58, CSDb release 261057, `cRSID-1.58-with-source-code.tar.gz` (md5 of the archive `c020bd22d4f243ef5f2762bd57dc9ef0`), fetched 2026-11-07 by `fpga/tools/sid_bard_fetch.sh` |
| Author | Mihaly Horvath (Hermit), 2026 |
| Licence | The archive has no LICENSE file. Its `README.txt` (here `cRSID-README.txt`) says: "License is still WTF: Do what the frick you want with this code, but it would be nice mentioning me as the original author." `upstream/README.txt` and `upstream/libcRSID.c` (line 2) say the same. Credit Hermit wherever the player is named. |
| `upstream/` | the archive's `libcRSID/` directory, **unmodified** (less one prebuilt test binary, `tests/simple_app/testapp_shared`) |
| Test tune | `upstream/tests/HerMiniSID.sid`, Hermit's own, shipped in the library: copied to `docs/music/hermini.sid` and `apps/zig/assets/sid/HERMINI.SID` for SID TEST |

## What we build: `patch.sh`

`patch.sh <out-dir>` copies `upstream/` and applies `patches/`, so upstream stays diffable. Each sed
patch must change its file, or the build stops. The sed patches are **bit-exact**: a tune loaded first
renders the same samples with or without them (the SID study's six tunes, host and BARD), and
`audio.c.sed` makes every load a first one.

| Patch | What | Why |
|---|---|---|
| `patches/C64_SIDrouting.c.sed` | the attenuator's `Output /= Attenuation` (and the HQ engine's `/= HQsampleCount`) become `ZDIV` (`config/zm_crsid.h`): a switch to constant divides | BARD has no divider: `__divsi3` is ~400 cycles, once a sample. A constant divide is a multiply on BARD (`-mno-div`) and in wasm |
| `patches/SID_OscWaves.c.sed` | the light pulse's `PHASEACCU_MAX / PhaseAccuStep` becomes `ZRECIP`: memoised per voice | the same divide a pulse voice a sample; the step only changes with the frequency registers |
| `patches/audio.c.sed` | the output dither's function-static LFSR becomes `zm_crsid_lfsr`, reset by every load | a tune's samples depended on what played before it; now a load is a fresh C64 (`zm_sid.c` also clears cRSID's globals) |
| `patches/SID_FilterCurves.h` | the light engine's filter cutoff table for 22.05 kHz, made by cRSID's own `tools/curvegen.c` at 22050 (`patches/curves.sh` regenerates it) | the stock table is for 44.1 kHz: at 22.05 every cutoff doubled. Data only. (The HQ engine's table, also regenerated, is unused) |

## Ours

| File | What |
|---|---|
| `zm_sid.c`, `zm_sid.h` | the door: `zm_sid_load` (PSID only: an RSID answers 2), `zm_sid_render` (s16 mono at 22050); raw SID for the BARD queue: `zm_sid_raw(model)` (a load of a static 2-byte PSID whose init and play are an RTS) and `zm_sid_write(reg, value)` (the 6502's store into the I/O page) |
| `config/zm_crsid.h` | `ZDIV`, `ZRECIP`, the LFSR's name, included before cRSID |
| `freestanding/` | the libc cRSID's non-PC build needs on wasm32-freestanding (`abs`, string functions for the song-length parser it never reaches, two unreached formatters) |
| `patch.sh`, `patches/` | above |

To update: replace `upstream/` with the new archive's `libcRSID/`, run `patch.sh` (a patch that no longer
applies stops it), `patches/curves.sh`, rebuild, run `node apps/sid_check.mjs` (native = wasm) and the
SID study's BARD bench (`fpga/tools/sid_bard_bench.sh`).
