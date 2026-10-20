# B.I.G. Demo digi tunes: the rip (2026-10-19)

The six files (`docs/music/digital/{Ace_2,Labello,Phantom_Of_The_Asteroid,Sanxion,Starpaws}.sndh`
and `docs/music/big/Labello.sndh`) are Grazey's SNDH conversions of THE DIGITAL SOLUTION screen's
music. The screen's own program is in the file (its text, "WELCOME TO THE DIGITAL SOLUTION OF
ALL", sits at $44216 of Ace 2), and with it one driver: Mad Max's sequencer for his 3-voice mixer.

- Image `$4D2` was assembled at `$44000`; the song and samples at `$60000` and `$80000`.
- Grazey's INIT (image `$9C`) relocates the code (longs in `$44000..$45FFF`), copies `$10A60`
  bytes of samples to a 64 KiB-aligned buffer, relocates the song, patches the driver, sets Timer A
  (vector `$134` = the handler, `$FA1F = $40`, `$FA19 = 1`: 9600 Hz), then calls the driver's
  init and the song's init with d0 = subtune - 1.
- The patches (a0 = the driver's `$44000`): `$45178` `subi.l #$50000,d7` -> 3 nops;
  `$44E78` the anti-rip check's beq -> bra; `$45548` the handler's `bclr #5,$FFFA11` -> rte;
  `$45DE0` the driver's own Timer D setup skipped; `$45E0A` its VBL hook -> rts; `$45358` the
  keyclick write -> nops; the silence pointer and `$FF8800` in its YM reset.
- PLAY (the SNDH header's third bra, `$44D26` in Ace 2) writes NO hardware: per voice it reads
  the pattern stream and leaves the mixer's state, the sample pointer at `$380/$386/$38C` and the
  step the handler adds every interrupt (the handler's own `addi.l` immediates).

`codecmp.py`, `holes.py`, `sig.py`: the code from PLAY on is the same in all six files outside the
absolute longs relocation moves (75 of them, plus the jump table). So one native driver covers
all six: `libs/zig/players/digi_big_play.zig`, `digi_big_note.zig`, `digi_big_env.zig`,
`digi_big_map.zig` (the variables read from the operands of the instructions that use them).

The scripts read the tunes from this directory: copy them in from `docs/music/digital/` first (they are not kept here).

`bench.sh`: `make snd-bench` for one of these tunes, run under one sim lock.
