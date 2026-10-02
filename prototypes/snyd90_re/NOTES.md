# Swedish New Year Demo 89-90 (Omega / SYNC / TCB, 1990-01-01) — RE notes

Source: `SNYD_90.ZIP` (fujiology `ST/T/TCB/`) -> `SNYD_90.MSA`, 10 sectors x 2 sides x 80 tracks.
`python3 msa2st.py SNYD_90.MSA SNYD_90.ST`. Not the 1989 demo (cart 76, `prototypes/snyd_re/`).

## Boot sector -> stage-2 loader at $600

* Boot: `floprd` track 0 side 0 sectors 2..5 -> `$40000`, then decrypts `$280` longs into `$600`
  with a chained EOR: `plain[i] = cipher[i] ^ key`, `key = plain[i]`. Initial key =
  `(SR << 16) | $FFE0` where SR is read right after `cmpa.l #$7000,a2` (boot buffer below `$7000`
  -> N,C set -> `$2709`). The `a2 - a3` part is always `-$20` (both pc-relative), so the key does not
  depend on the TOS. The boot then NOPs its own `rts` and falls into `rte` -> `$600` (SR `$2709`).
  `boot_decrypt.py` -> `loader600.bin` (key `$2709FFE0`, right first time).
* The string "HI OVERLANDERS ALREDY TRYING TO STEAL NEW DEMO ROUTINES?" is in the boot sector.

## Loader ($600)

* Own FDC driver (`$97C`, DMA + Timer-less polling via MFP GPIP bit 7 vector `$11C`): reads `count`
  sectors on ONE side from linear sector `start` (track = start/10, sector = start%10 + 1).
* Part table `$CA8`, 18-byte entries `start.w count.w side.w load.l packed.l entry.l`.
  Packed parts go through `$7D8` (ByteKiller: stream read backwards, unpacked length, checksum,
  LSB-first bits with a sentinel) and then `$8C8` (a word-RLE expansion pass). `depack.py`
  transcribes both and asserts the loader's own checksum (d5 == 0): all six packed parts pass.
* Flow: Left Shift held at boot (`$FFFC02 == $2A`) -> part 7 first; then part 8 (intro), then
  loop { part 0 (menu) -> d0 -> part d0 }. Menu VBL `$1562`: F1..F6 (`$3B..$40`) -> d0 = 1..6.

| # | trk/side | load | packed | unpacked | what (strings) |
|---|---|---|---|---|---|
| 0 | 1/0  | $1000 | -       | 71680  | MENU (TFE of Omega, gfx Red, music Mad Max; "five 64x62 4-plane sprites") |
| 1 | 15/0 | $1000 | $10C28 | 211364 | F1 OMEGA: ball-bending scroller (TFE) |
| 2 | 11/1 | $1000 | $7C88  | 118784 | F2 OMEGA: "Liesen dist, HAQ scroll, Red logos" |
| 3 | 60/0 | $18000| $C47C  | 163840 | F3 OMEGA (the "funny Mupp demo" per F2's text) — TBC |
| 4 | 29/0 | $7FE4 | -       | 87040  | F4 TCB (An Cool, Mad Max) — PRG header at $7FE4, entry $8000 |
| 5 | 70/0 | $C000 | $6C70  | 68202  | F5 SYNC — TBC |
| 6 | 0/1  | $C000 | $D348  | 93966  | F6 SYNC — TBC |
| 7 | 18/1 | $C000 | -       | 261120 | hidden (Left Shift at boot): sample data |
| 8 | 46/0 | $1000 | -       | 71680  | intro, loaded once before the menu |

`parts.py` rips them all to `parts/p<i>_<load>.bin` (memory images at `load`).

## Menu (part 0, `$1000`)

* `jsr $79C4` d0=1 = music init (Mad Max). Palette `$384C`. VBL `$1562` counts frames in `$158A`;
  main loop `$109A` waits it, `jsr $29E0` per frame, returns when `$10B8` (word) != 0.
* Init `$10C2` GENERATES compiled sprite code (`$11C8`/`$1294`: runs of skip / and-or / movem
  stores from each sprite's mask) — the "fastest sprite routines" of the scrolltext.
* Scroller `$15CC`: 16x13 4-plane font at `$1A5A + (c-'A')*$68` (space = `$19F2`), text `$1718`
  (`$FF` = restart), 4 preshifted 4-px buffers `$38C4/$4904/$5944/$6984`, 4 px a frame, every row
  doubled, copied to screen + `$5780` (line 140), 26 lines, full width.
