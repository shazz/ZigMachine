# The VGM engine: Mega Drive music on our own chips, MIT

`zm_vgm.h` loads a `.vgm` (or a `.vgz`, inflated in place) and renders its YM2612 (`libs/c/ym2612`) and
SN76489 (`libs/c/sn76489`) as stereo s16 at the YM2612's clock / 288 (26,633 Hz NTSC). All of it is our
own code, written from the format and hardware documents, integer only. The same C runs on BARD
(`fpga/host/audio_vgm.c`, native), in `machine-audio.wasm` (`machine/audio/vgm.zig`, the page) and in the
native host. The player's output stage is C too (`zm_vgm_out.c`: linear to 44.1 kHz, the hi/lo split), so
`libs/zig/players/vgm.zig` only places the four Paula rings and triggers them.

| File | What |
|---|---|
| `zm_vgm.h`, `zm_vgm.c` | the door: `zm_vgm_load(file, len, cap)`, `zm_vgm_rate()`, `zm_vgm_render(lr, n)`; the two chips' gains |
| `vgm_seq.h`, `vgm_seq.c` | the sequencer (VGM specification 1.71, vgmrips.net): waits, 0x52/0x53, 0x50, 0x4F, 0x66 + loop, 0x67 type-0 data blocks (up to 16, one bank), 0x8n, 0xE0 |
| `vgm_stream.c` | 0x90-0x95 DAC stream control (one stream, to the YM2612's DAC) |
| `zm_vgm_out.c` | the player's output: mp3_resample's linear to 44.1 kHz and mp3_out's hi/lo bytes, in C (native on BARD) |
| `zm_inflate.h`, `zm_inflate.c` | gzip (RFC 1952) / DEFLATE (RFC 1951) for `.vgz` |
| `zm_mem.h` | memset / memmove: libc's, or the compiler runtime's in the freestanding wasm build |
| `vgm_write.py`, `test_vgms.py` | a VGM writer; our single-feature VGMs (algorithms, feedback, envelope, LFO, detune, SSG, channel 3, DAC, PSG) |
| `make_tune.py` | KESTREL FM, VGM TEST's tune (`docs/music/kestrel_fm.vgm`): original, every part of both chips busy |
| `vgm_trim.py` | a VGM cut to start mid-tune, small, for BARD benches |
| `fpga/tools/vgm_render.c`, `fpga/tools/vgm_count.c` | the native renderer (the harness's, `-p` the output stage); operators computed a frame (`-DZM_YM_COUNT`) |
| `gens_compare.py`, `gens_compare.sh` | LOCAL: our FM against a reference render (the Gens core on Matt's machine) |

## Limits

- The file sits whole in song RAM: up to 983,040 bytes, a `.vgz` and what it inflates to likewise (status 5,
  "too big for the song RAM", or 4). Most Mega Drive VGMs fit; Sonic 1's Staff Roll (1.05 MB) does not.
- A malformed loop (a pass that waits nothing) ends the tune; a DAC stream rate is held to 4 writes a chip sample.
- One YM2612 and one SN76489. Second chips (bit 30 of a clock), other chips' commands, and data blocks of other
  types are skipped. No timers, so no CSM.
- Writes inside one chip sample collapse (the last wins): at 26.6 kHz a DAC stream faster than that loses
  samples, as on the Gens spike.

## Accuracy (black-box references, FM only)

`gens_compare.sh 1|2 <vgm>...` renders our FM and a reference's (libvgm's vgm2wav forced to a YM2612 core, PSG
muted, on Matt's machine only: GPL, never committed) and prints the best lag, the gain, the correlation and the
residual. Two references: Gens (the BARD spike's core) and Genesis Plus GX. Sonic 1's 19 tunes, 20 s each:

| rate | vs Gens | vs Genesis Plus GX |
|---|---|---|
| 53,267 Hz (div 1) | 0.891 - 0.996, median 0.966; Green Hill Zone 0.991 | 0.950 - 0.998, median 0.992; Green Hill Zone 0.996 |
| 26,634 Hz (div 2, the BARD player's) | 0.862 - 0.991, median 0.951; Green Hill Zone 0.986 | 0.933 - 0.996, median 0.982; Green Hill Zone 0.993 |

Single features at 53,267 Hz (Gens / GPGX / Nuked OPN2): envelope 0.969 / 0.998 / 0.801, detune + multiple
0.997 / 0.997 / 0.970, channel 3 special 0.992 / 0.9997 / 0.989, DAC 0.997 / 0.997 / 0.910, algorithms 0.961 /
0.984 / 0.895, feedback 0.840 / 0.934 / 0.898 (FB 6-7 are chaotic: level and spectrum match, samples cannot), LFO
0.775 / 0.768 / 0.762 (rate and depth match; the PM phase drifts), SSG-EG 0.43 / 0.62 / 0.60 (the references
disagree with each other: not proven). Nuked runs a cycle-exact pipeline at its own phase, so it correlates
lower everywhere. The PSG matches the reference's pitches and levels; its noise only by loudness.

## Proof in the gate

`apps/vgm_check.mjs`: machine-audio.wasm = the native build, block for block (11 tunes, local ones too);
each feature VGM's render = `apps/vgm_expected.json` (our own output, pinned); the player = the engine
resampled `>> 1`; five refusals. `--break envelope | lfo | feedback | dac | noise` each mutate one rule and
must fail that feature's pinned hash. `apps/vgm_test_check.mjs`: the VGM TEST cart's keys and bytes.

## BARD load

`fpga/cycles/sound/svgmbench.c` (the engine alone, `snd-cbench`) and `snd-bench SONG=<x>.vgm` (the whole
player), on the board core's model (`build/soc_hp_snd_dyn8sx`, KESTREL v1.3's BARD). Numbers:
`fpga/review/YM2612_BARD_STUDY.md` section 6.
