# ayumi in integers: the AY / YM chip every renderer shares

Peter Sovietov's ayumi (MIT, modifications by Megus in ChipNomad; upstream's `chipnomad_lib/external/ayumi/LICENSE`),
the chip model only, in integers: tone counters, the 17-bit noise LFSR, the 32-step envelope and its 16 shapes, the AY
and YM DAC tables (Q15), the pans. A sample is the exact average of the chip's ticks (clock / 8) it spans, a box filter
in place of upstream's cubic interpolator and FIR; the chip is stepped event to event; a one-pole DC blocker (~14 Hz at
any rate). No float anywhere and no divide in the per-sample path: BARD has neither an FPU nor a divider.

| Who | How |
|---|---|
| ChipNomad on ZIGGY | `apps/ports/chipnomad/kestrel_ayumi.cpp`: upstream's ayumi API (float clock and pans) over `zm_ay.h` |
| BARD, ZIGGY with the players, the native host | `fpga/host/audio_ay.c` answers the players' `machineAy*` imports with `zm_ay_bank.c` |
| the page | `machine-audio.wasm` (`machine/audio/ay.zig`), the same `zm_ay_bank.c` |

`zm_ay_bank.h` is the BARD queue's AY device: eight chips behind one address space (`addr = 0xA000 + chip x 16 + reg`,
register 14 configures a chip, 15 sets its pans, `0xA080 + chip` its gain), rendered at the queue's 44.1 kHz, summed.

## Proof

`sh libs/c/ayumi/check/check.sh` (gated: `build.sh`, `ports_chipnomad`): 3,000 random chips, 9.84 M samples, against the
cart's ayumi before the move (`kestrel_ayumi.cpp` at 0de82761, built from git): every sample the same, before the DC
blocker at 22050 and 44100 Hz and after it at 22050 (at 44100 the core halves the corner to keep ~14 Hz; the old file
kept the 22050 Hz shift at every rate). Its set-up was float; the core's is integer:

- pans: `(int)(sqrtf(k / 200) x 32768 + 0.5)` is a 201-entry table, equal to the float for every pan ChipNomad's stereo
  modes make (0.5 -/+ separation / 200, both sides);
- the clock: ticks a sample = `clock x 8192 / rate`, equal to the float step's for every clock ChipNomad offers (0.75,
  1, 1.75, 1.7734, 2 MHz) at 22050, 44100 and 48000 Hz; of the 3.5 M integer clocks from 0.5 to 4 MHz, 3.7 % (22050)
  to 1.5 % (48000) land 1/65536 of a tick a sample apart (a phase drift of a tick every 1.5 s at 44.1 kHz).
`--break` (tone writes off by one) must fail it.
