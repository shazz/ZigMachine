# Our YM2612 (OPN2): the Mega Drive's FM chip, MIT

A clean-room model in integer C: written from the hardware documentation, never from an emulator's
source (Gens, MAME, Nuked, GPGX, ymfm). The Gens core was used only as a black box, through its
rendered samples (`libs/c/vgm/README.md`, "Accuracy"), on Matt's machine; nothing of it is in the repo.

| File | What |
|---|---|
| `ym2612.h` | the state and the API: `ym2612_reset(div)`, `ym2612_write(port, reg, val)`, `ym2612_render(lr, n)` |
| `ym2612.c` | the register map: globals, operators, frequencies (the A4/AC latches), algorithm, pans |
| `ym2612_eg.c` | the envelope generator (rates, key scaling, SSG-EG), key on/off, the phase increment (detune, multiple) |
| `ym2612_render.c` | the operators in the log domain, the 8 algorithms, feedback, the LFO, the DAC, the stereo mix |
| `gen_tables.py` -> `ym2612_tables.h` | the constant tables, each built from its documented definition (`--check` in the gate) |

## Sources

- YM2608 (OPNA) application manual: the FM register map, DT1 detune table, the key code, rates and key
  scaling, sustain levels, LFO frequencies and the AM / PM depths.
- Sega Genesis Software Manual, YM2612 chapter: the register map, the operator order S1 S3 S2 S4, the DAC
  (0x2A, 0x2B), channel 3's special mode frequencies (A9 op 1, AA op 2, A8 op 3).
- Nemesis's YM2612 hardware notes (SpritesMind forum, 2008-2009): the log-sine and exponent ROM shapes,
  the EG clocked every 3 samples with its 8-step increment patterns, the attack curve, SSG-EG.

## Choices, measured against the reference

- **Rate.** The chip computes one sample every 144 clocks (53,267 Hz NTSC). `div` 2 renders every other one
  (26,634 Hz): phases, the EG (every 3 chip samples) and the LFO (a Q16 step) advance two chip samples a
  render, exactly. The BARD player uses div 2; div 1 is the chip's own rate.
- **Attack.** `att += (~att x inc) >> 3`: Nemesis writes `>> 4`, which against the reference attacks at half
  the speed (envelope test: corr 0.969 with `>> 4`, 0.997 with `>> 3`).
- **Channel clip.** The 14-bit accumulator saturates at +-8191 (the hardware's width). The Gens reference
  clips at +-12287 instead; only a patch with several full-level carriers tells them apart.
- **Feedback.** Op 1 hears the mean of its last two outputs, `(o1 + o2) >> (10 - FB)`; FB 6 and 7 are chaotic
  on any implementation, so they match by level and spectrum, not sample for sample.
- **SSG-EG** follows the hardware notes (4x rate below 0x200, then repeat, alternate or hold). The Gens
  core ignores the repeat, so the SSG test does not correlate with it.
- **Not modelled:** the timers and CSM key-on, the status register, the DAC's ladder distortion.

## BARD

No float, no divide in the per-sample path (BARD is rv32i + Zmmul: a `/` is a 400-cycle libgcc call), 1.3 KB
of tables, the state ~1.5 KB: all inside BARD's 16 KB D$. Released channels cost nothing (the EG marks them
and the render skips them); an operator at attenuation 832 or more returns 0 before its table reads (exact:
the sine's loudest step is 0).
