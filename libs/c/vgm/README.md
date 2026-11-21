# The VGM engine: Mega Drive music on our own chips, MIT

`zm_vgm.h` loads a `.vgm` (or a `.vgz`, inflated in place) and renders its YM2612 (`libs/c/ym2612`) and
SN76489 (`libs/c/sn76489`) as stereo s16 at the YM2612's clock / 288 (26,633 Hz NTSC). All of it is our
own code, written from the format and hardware documents, integer only. The same C runs on BARD
(`fpga/host/audio_vgm.c`, native), in `machine-audio.wasm` (`machine/audio/vgm.zig`, the page) and in the
native host; `libs/zig/players/vgm.zig` resamples it to 44.1 kHz and plays it on the four Paula channels.

| File | What |
|---|---|
| `zm_vgm.h`, `zm_vgm.c` | the door: `zm_vgm_load(file, len, cap)`, `zm_vgm_rate()`, `zm_vgm_render(lr, n)`; the two chips' gains |
| `vgm_seq.h`, `vgm_seq.c` | the sequencer (VGM specification 1.71, vgmrips.net): waits, 0x52/0x53, 0x50, 0x4F, 0x66 + loop, 0x67 type-0 data blocks (up to 16, one bank), 0x8n, 0xE0 |
| `vgm_stream.c` | 0x90-0x95 DAC stream control (one stream, to the YM2612's DAC) |
| `zm_inflate.h`, `zm_inflate.c` | gzip (RFC 1952) / DEFLATE (RFC 1951) for `.vgz` |
| `vgm_write.py`, `test_vgms.py` | a VGM writer; our single-feature VGMs (algorithms, feedback, envelope, LFO, detune, SSG, channel 3, DAC, PSG) |
| `make_tune.py` | KESTREL FM, VGM TEST's tune (`docs/music/kestrel_fm.vgm`): original, every part of both chips busy |
| `vgm_trim.py` | a VGM cut to start mid-tune, small, for BARD benches |
| `gens_compare.py`, `gens_compare.sh` | LOCAL: our FM against a reference render (the Gens core on Matt's machine) |

## Limits

- The file sits whole in song RAM: up to 982,016 bytes, a `.vgz` and what it inflates to likewise (status 5,
  "too big for the song RAM", or 4). Most Mega Drive VGMs fit; Sonic 1's Staff Roll (1.05 MB) does not.
- One YM2612 and one SN76489. Second chips (bit 30 of a clock), other chips' commands, and data blocks of other
  types are skipped. No timers, so no CSM.
- Writes inside one chip sample collapse (the last wins): at 26.6 kHz a DAC stream faster than that loses
  samples, as on the Gens spike.

## Accuracy (against the Gens core, black box, FM only)

`gens_compare.sh 1|2 <vgm>...` renders our FM and the reference's (libvgm's vgm2wav forced to Gens, PSG
muted) and prints the best lag, the gain, the correlation and the residual. Sonic 1's 19 tunes, 20 s each:

| rate | correlation | e.g. Green Hill Zone |
|---|---|---|
| 53,267 Hz (div 1, both) | 0.920 - 0.996, median 0.978 | 0.992 (residual 18 dB) |
| 26,634 Hz (div 2, both: the BARD player's) | 0.875 - 0.991, median 0.959 | 0.987 |

Single features at 53,267 Hz: envelope 0.997, detune / multiple 0.997, channel 3 special 0.9994, DAC 0.997,
algorithms 0.961 (the reference clips a channel at +-12287, we at the chip's +-8191), feedback 0.840 (FB 6-7 are
chaotic: level and spectrum match, samples cannot), LFO 0.774 (rate and depth match; the PM phase drifts),
SSG-EG 0.43 (the reference does not repeat SSG envelopes; we follow the hardware notes). The tunes that
correlate least (Game Over, Final Zone, Robotnik) are FB 7 throughout. The PSG matches the reference's
pitches and levels; its noise only by loudness.

## Proof in the gate

`apps/vgm_check.mjs`: machine-audio.wasm = the native build, block for block (11 tunes, local ones too);
each feature VGM's render = `apps/vgm_expected.json` (our own output, pinned); the player = the engine
resampled `>> 1`; five refusals. `--break envelope | lfo | feedback | dac | noise` each mutate one rule and
must fail that feature's pinned hash. `apps/vgm_test_check.mjs`: the VGM TEST cart's keys and bytes.

## BARD load

`fpga/cycles/sound/svgmbench.c` (the engine alone, `snd-cbench`) and `snd-bench SONG=<x>.vgm` (the whole
player), on the board core's model (`build/soc_hp_snd_dyn8sx`, KESTREL v1.3's BARD). Numbers:
`fpga/review/YM2612_BARD_STUDY.md` section 6.
