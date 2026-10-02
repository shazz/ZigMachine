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
| 0 | 1/0  | $1000 | -       | 71680  | MENU (TFE of Omega, gfx Red, music Mad Max; "five 64x62 4-plane sprites") -- PORTED |
| 1 | 15/0 | $1000 | $10C28 | 211364 | F1 OMEGA: ball-bending scroller (TFE) -- PORTED |
| 2 | 11/1 | $1000 | $7C88  | 118784 | F2 OMEGA: "Liesen dist, HAQ scroll, Red logos" -- PORTED |
| 3 | 60/0 | $18000| $C47C  | 163840 | F3: the ball-curve editor ("funny Mupp demo" per F2's text?), bottom border -- not ported |
| 4 | 29/0 | $7FE4 | -       | 87040  | F4 TCB (An Cool, Mad Max) -- PRG header at $7FE4, entry $8000 (jmp $F130) -- not ported |
| 5 | 70/0 | $C000 | $6C70  | 68202  | F5 SYNC: giant scroller, full overscan -- not ported |
| 6 | 0/1  | $C000 | $D348  | 93966  | F6 SYNC: vector balls, text writer, logo in the lower border -- not ported |
| 7 | 18/1 | $C000 | -       | 261120 | hidden (Left Shift at boot): sample data |
| 8 | 46/0 | $1000 | -       | 71680  | intro (Spectrum 512 title picture), loaded once before the menu -- PORTED |

`parts.py` rips them all to `parts/p<i>_<load>.bin` (memory images at `load`).

## Menu (part 0, `$1000`)

* `jsr $79C4` d0=1 = music init (Mad Max). Palette `$384C`. VBL `$1562` counts frames in `$158A`;
  main loop `$109A` waits it, `jsr $29E0` per frame, returns when `$10B8` (word) != 0.
* Init `$10C2` GENERATES compiled sprite code (`$11C8`/`$1294`: runs of skip / and-or / movem
  stores from each sprite's mask) — the "fastest sprite routines" of the scrolltext.
* Scroller `$15CC`: 16x13 4-plane font at `$1A5A + (c-'A')*$68` (space = `$19F2`), text `$1718`
  (`$FF` = restart), 4 ring buffers of 13 rows x 320 bytes `$38C4/$4904/$5944/$6984` (one per 4-px
  shift; the new column written at col and col+160), 4 px a frame, copied to screen + `$5780`
  (line 140), 13 lines, full width.
* Sprites: 11 bitmaps listed at `$386C` (ptr, flag: flag != 0 -> 48 px wide, else 64; 62 rows), sets
  `$1596` (5: OMEGA), `$15AC` (4: SYNC), `$15BE` (3: TCB, the C shared), 8 preshifts of 2 px. Head:
  Y = walker $2F68 + walker $2F86, X = $2FA4 + $2FC2 (`$2F2E`: table of longs $3018..$3818, value =
  low word, (v + $8000) * amp >> 16; a (count, step) list per walker), ring of 25 at `$2D96`, sprites
  6 entries apart, oldest drawn first. Phases at `$29CA..$29DE`: 500 idle, slide up 64 lines with the
  Y amplitudes, 100 pause, swap set, slide back.

## Menu: verified

`menu_model.py` (Python) and `apps/zig/scenes/snyd_90/menu*.zig` reproduce Hatari's RAM (both screens,
phase variables, walkers, ring, scroller variables + buffers, clear lists) at iterations 0, 99, 530
(mid-slide) and 999 (after the swap to the SYNC set): dumps `hatari/menu_it*.bin`, taken at `$10A8`
(the main loop's `jsr $29E0`), iteration count from `$29CA`. Phase-machine detail that cost a diff:
when the slide-down ends the code branches to `$2AA0`, so the idle counter also ticks that iteration.
Music: the menu's COSO replay + module ($79C4..+$4554) as `snyd90.sndh` (6 subtunes; menu 1, intro 4).
The oracle's YM registers (below) and the SNDH's on the sealed YM are equal on all 1500 frames at
lag 0. Archive: best module match Stormlord (155/352 windows: shared instruments, other module).

## Intro (part 8): verified

Spectrum 512 layout (screen $5724 + 199 x 48-word palettes $D424). `spu.py` decodes it with the
standard boundary formula and matches Hatari's capture on every pixel, once colour 0 of set 0 (never
written: the loop starts at $FF8242) is taken as the previous line's set-2 colour 0. Borders black.

## The oracle: m68run (Musashi)

`m68run.c` (from `../snyd_re/tcb/`; Musashi sources in `../snyd_re/tcb/m68/`, build:
`cd m68 && gcc -O2 -I. -o ../m68run ../m68run.c m68kcpu.c m68kops.c softfloat/softfloat.c -lm`) runs
the ORIGINAL code on a 512 KB RAM image. Added here: `exec:START:STOP` (a main loop's body that is not
a subroutine), `loop:N:vbl:ADDR:exec:S:E`, `search:` with `exec:`, `dump:FILE`, `hw:FILE` (the $FF8000
register file: palette at +$240) and `ymlog:FILE` (16 YM registers after each loop frame). Start
images: Hatari RAM at a part's entry (`hatari/<part>_entry.bin`, break on the entry PC guarded by the
part's own first word).

## F2 (part 2, $1000): OMEGA "Liesen dist" + "HAQ scroll" -- PORTED

* Entry `$1174`: set-up to `$15EC` (clears $70000..$80000, palette $6908, unpacks $134D6 -> $1D000 and
  $10CD6 -> $46400 with its own unpacker $6852, 16 logo preshifts listed at $8738, font 4x preshifted
  $189D6 -> $10CD6, the sine table $1C68 x160, music init `$8836` d0=0). VBL `$162E` sets `$164A`;
  Space released ($B9) -> `$6828` (restore, rts to the loader). Main loop body `$1600..$161A`.
* Oracle check: set-up + 193 frames == Hatari's `hatari/f2_a.bin` (taken at $1600, VBL 3055) except the
  VBL flag, the saved SP ($87E6) and the stack. The asset is the oracle's RAM after the set-up.
* Per VBL: eori $8000 on $87FC (draw buffer $87FA: $70000/$78000) and on $8203 (shown next VBL);
  clr $8240; `$11E0` logo; `$1650` scroller. Details in `f2_logo.zig` / `f2_scroll.zig` (self-modifying:
  `$1114` patches 40 movep displacements for the draw $149C.. and clear $13B8..; the scroller patches
  its `lea d(a3),a0` at $17DC.. and the clear routine of the next frame at $1A78 / $1B22).
* Display timing: VBL k shows the screen VBL k-1 drew, palette as the script leaves it early in VBL k;
  the scroller clear of that screen comes late (after ~125k cycles, beam below the scroller).
* `oracle_expect.py f2` -> f2_test.zig CRCs (1..1500 VBLs: all match). Music: TFMX module at $91B2,
  replay $8836..$AF16 wrapped (`f2.sndh`, d0 stub -> 0): YM equal to the oracle's on 1500/1500 frames.

## F1 (part 1, $1000): OMEGA ball bending scroller -- PORTED

* Entry `$1000` (SR $2709, A7 $5F4 from the loader: the set-up clears up to $80000, so the oracle
  must keep the loader's stack). Copies the ball picture $2CCA4 -> $78000 (one screen), palette
  $2CC28 (then OVERWRITTEN by the path table: kept as constants in f1.zig), music init `$4078` d0=0,
  builds 200 paths x 314 (word offset, bit) steps at $1D6D4 from the x table at $2CC24. VBL `$10EE`:
  Space ($39 press) sets $10EA, music play `$3B50`, counter $10EC. Main body `$10C6..$10D2` = `$1234`.
* `$1234`: per line, erase list then draw list (10 words each at $138C + 40*line; counts at $35EC)
  of points walking the path from $4E4 down to 0 by 4 on plane 3 ($78006); a finished point calls
  the handler $390C + 4n, which moves n words down (one more than the live ones). Then the feed:
  every $140 VBLs a letter ($39F0, '@' = blank, glyph $5B24 + (c-'@')*$E10, 9 words a line), per
  line a delay ($345C) then a new point at $4E4, erase/draw alternating ($32CC).
* Real-time oracle: VBL-locked (only the first iteration overlaps a VBL: it starts mid-frame).
  Iteration-locked oracle == Hatari `hatari/f1_a.bin` at iteration 515 within 22 bytes (VBL vars,
  stack, replay). The set-up takes 43 VBLs on the ST (picture shown, no music yet); not reproduced.
* Music: Jas C. Brooke's Overlander (the replay at $3B24..; `Brooke_Jas_C/Overlander.sndh` 145/154
  windows): the archive's subtune 1 writes the oracle's YM registers on 1500/1500 frames at lag 0.
  (The boot sector's joke at the Overlanders, and Omega play their tune.)

## Real-time oracle (m68run `rt:`) and what it says about the other parts

`rt:NVBL:PC:PHASE:STOP[:TB]` runs a part from its entry with every instruction rounded to 4 cycles,
a VBL every 160256 cycles (first one PHASE cycles in: Hatari's FrameCycles at the entry breakpoint)
and optionally a Timer B a frame. On F4 it reproduces Hatari's RAM after 300 VBLs to 8 bytes; the
iteration-locked oracle does not. Entry phases: F1 144460, F2 18964, F3 76028, F4 77416, F5 27408,
F6 86132 (from the breakpoints; entry dumps `hatari/f*_entry.bin`, menu snapshot `hatari/state-0003`).
`RT_LOG=1` prints where each VBL lands; `RT_TRAP=1` the PCs before a jump below $600.

* **F4 (part 4, TCB/An Cool: logo blocks, bob ring, 3 star layers, magenta scroller; entry
  `$F130`, VBL `$F2BE`, Timer B `$F39E` at line 183: colours 4..11 red -> magenta)** -- NOT PORTED.
  Its iterations overrun the VBL about one frame in six (VBLs land inside `$13xxx`, `$C4xx`, ...);
  the VBL handler toggles `$F3C0`, swaps the star clear lists and both screen pointers and plays the
  music, so a VBL inside an iteration changes what the rest of that iteration draws, and frames drop.
  A faithful port needs the 68000's cycle cost of every iteration (a cycle model of the port's work,
  or a schedule recorded from the real-time oracle -- not periodic as far as looked).
* **F3 (part 3, $18000, TCB/OMEGA ball-curve editor, "SX SY GX GY")** -- NOT PORTED. VBL-locked in the
  real-time oracle, but most of its work runs INSIDE the VBL handler `$1888E` (screen flip
  $60000/$70000, palette, Timer B chain `$18626`/`$18654` from line 39, `$18B1A`), and Timer B
  `$18776` opens the bottom border by syncing on the video counter and jumping into nops. Interactive
  (keys edit the curve parameters). Display model to build: the rasters + the opened bottom border.
* **F5 (part 5, $C000, SYNC giant scroller in full overscan)** -- NOT PORTED. VBL-locked. VBL `$17D42`
  arms Timer A (delay $67/4): `$179A0` opens the top border, syncs on $8209, then `$1525E` runs the
  fullscreen lines through 8 `jsr` whose targets are PATCHED at run time (per-line routines at
  `$1540C..`), and loads a second palette ($195DA) at the bottom. The main loop works in the spare
  lines (`$17F56` flag). Display model to build: each line's start address / length from the patched
  line routines (cf. cart 76's TCB #1 230-byte-line model).
* **F6 (part 6, $C000, SYNC vector balls + text writer + sparkly SYNC logo in the lower border,
  raster lines through the borders)** -- NOT PORTED. Seeds a choice of 4 settings from Timer C's
  running counter (`move.b $FA23,d0`: random on the ST), uses Timers A/B/C and a VBL, and runs its
  main loop every SECOND VBL (`$12AEC` >= 2: 25 Hz).
* **Part 7 (Left Shift at boot, 261 KB at $C000)**: sample data of a hidden part -- not looked at.
