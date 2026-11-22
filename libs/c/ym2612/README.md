# Our YM2612 (OPN2): the Mega Drive's FM chip, MIT

A clean-room model in integer C: written from the hardware documentation, never from an emulator's
source (Gens, MAME, Nuked, GPGX, ymfm). Emulator cores (Gens, Genesis Plus GX, Nuked) were used only as black boxes, through their
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

## Choices, measured against three black-box references

The references are libvgm's Gens, Genesis Plus GX and Nuked OPN2 cores, rendered on Matt's machine only
(`libs/c/vgm/README.md`, "Accuracy"); where they disagree the hardware notes decide.

- **Rate.** The chip computes one sample every 144 clocks (53,267 Hz NTSC). `div` 2 renders every other one
  (26,634 Hz): phases, the EG (every 3 chip samples) and the LFO (a Q16 step) advance two chip samples a
  render, exactly. The BARD player uses div 2; div 1 is the chip's own rate.
- **Attack.** `att += (~att x inc) >> 4`, as the notes write it. Gens attacks twice as fast (`>> 3` fits it
  better: envelope test 0.997 against 0.969), but GPGX (0.998 against 0.972) and Nuked (0.801 against 0.785)
  both prefer `>> 4`.
- **Channel clip.** The 14-bit accumulator saturates at +-8191 (the hardware's width). Gens clips at +-12287;
  only a patch with several full-level carriers tells them apart (algorithms test: GPGX 0.984, Gens 0.961).
- **Feedback.** Op 1 hears the mean of its last two outputs, `(o1 + o2) >> (10 - FB)`; FB 6 and 7 are chaotic
  on any implementation, so they match by level and spectrum, not sample for sample.
- **SSG-EG** follows the hardware notes (4x rate below 0x200, then repeat, alternate or hold). No reference
  agrees with another here (ours against Gens 0.43, GPGX 0.62, Nuked 0.60): not proven.
- **Not modelled:** the timers and CSM key-on, the status register, the DAC's ladder distortion.

## BARD

No float, no divide in the per-sample path (BARD is rv32i + Zmmul: a `/` is a 400-cycle libgcc call), 1.3 KB
of tables, the state ~1.5 KB: all inside BARD's 16 KB D$. Released channels cost nothing (the EG marks them
and the render skips them); an operator at attenuation 832 or more returns 0 before its table reads (exact:
the sine's loudest step is 0).
