# Nitrowave Demo (Naos, 1990) — RE notes

Demozoo 72475. Generation 4 competition (theme: the 3615 GEN4 minitel server).
Port: cart 82, `naos_nitrowave` (apps/zig/scenes/naos_nitrowave*.zig).

## Sources

- `NITROWAV.ZIP` -> `NITROWAV.MSA` (the real disk). `msa2st.py` -> `NITROWAV.ST`,
  `fatx.py NITROWAV.ST disk` (BPB says 0 reserved sectors; FAT is really at
  sector 1, fatx.py patched). The boot sector is ZEROED in this image (LISEZ.MOI:
  the original's executable boot sector only printed "please wait" and is not
  needed). **Disk files are UNPACKED** -> used these.
- `NITRO_F.ZIP` = a later file/HD version: `NITRO.PRG` loader + LSD!-packed
  `*.BIN` (+ MENU.BIN as a PRG). Same content, packed. Not used.

| file | size | what |
|---|---|---|
| AUTO/MENU.PRG | 252865 | BATTLETEC menu (Freddi; overscan by Aragorn; music Mad Max; gfx ATM). TEXT 50168, DATA 201848, BSS 158 |
| DEMO_RIC.BIN | 111376 | F1: MULTISPRITES (Ric) |
| B_SPRITE.BIN | 95078 | F2: BIGSPRITE + OVERSCAN (Aragorn) |
| DAMIER3D.BIN | 264526 | F3: SAPRISTI 3615 GEN 4 (Aragorn): overscan, checkerboards top+bottom, parallax, logo distort, scroller. Loads at $400 (jsr $a76 = file+$676) |
| LISEZ.MOI | | French readme (credits, F-key freeze keys) |

## Hatari

shirazmcp's single session was held by a sibling agent, so Hatari was run
directly: `SDL_VIDEODRIVER=dummy hatari --machine st --memsize 1 --tos
tos162fr.img --disk-a NITROWAV.ST --borders on --fast-forward on
**--frameskips 0** --avirecord --avi-vcodec png ...` and `avi_frames.py` splits
the AVI (no ffmpeg on this box). **`--frameskips 0` is essential**: without it
Hatari's auto frameskip renders 1 frame in 6 and the AVI repeats it, which
looked like a timing bug in the model for an hour.
- TOS 1.62 forces STE; MENU.PRG's TEXT loads at **$AA9A**.
- Debugger scripting works: `--parse start.ini` with `b VBL = N :once :file x.ini`
  and tracepoints `b pc = $X :trace :file hbl.ini` (`e HBL`).
- `run_part.sh N VBLS` patches the key test at $AFD6 into `jmp` F<N>'s handler at
  VBL 1400 and records the part (parts take ~1500 VBLs to load off the floppy).
- Menu VBL handler ends at line 291, main loop done by line ~303 of 313: no
  overrun, one main-loop pass per VBL.

## Menu (MENU.PRG, relocated to 0)

- $0..$2E4: machine test — generates the fullscreen routine three ways
  (line slots $164/$34, $168/$30, $16C/$2C) and checks it; screen black. Not ported.
- Picture: $C418, laid out as the screen (160-byte top line + 260 x 230 bytes);
  palette $C3F8. Copied to both screens $69100 / $59A00 ($AA..$E6).
- VBL $78800 = template $E10..$15D2 + fragment stream $1688..$C3F8. Fragment =
  (cycles.w, nwords.w, code); `$1618` packs them into each line's free cycles
  (nop-padding). `frags.py` linearises (5823 fragments, 109728 cycles);
  `vbl68k.py` interprets the data instructions; `sem_extract.py` reads the shape:
    - erase: path word e, 32 rows x 224 bytes screen+e <- picture+e
    - draw: path word d, a5 = screen+d+16, 22 columns (8 bytes apart) x 31
      rows: planes 0..3 &= mask long, planes 0,1 |= gfx long, plane 2 |=
      gfx plane-2 word, EXCEPT rows 4 and 5 which take the gfx PLANE-3 word
      (`move.l $284(a4),d2` / `or.w d2` — quirk of the original, ported).
  `menu_sem.py` = those loops; identical RAM to the interpreter for 1500 frames.
- Path $1B956: (erase, draw) word pairs, erase[k] = draw[k-2] (double buffer);
  rows 9..216 step 9 down then 10 up...; reset every $2CA frames ($76C, $3D904).
- Tables (27 longs): gfx A $1C4CA, gfx B $1C542, mask A $1C5BA, mask B $1C632.
  $630 shifts the CURRENT pair one entry; entry 26 is never written (blank).
  Font sheets (low-res, 160 bytes/row, letters 48x31 every 24 bytes, rows of six
  letters every $14A0): gfx A $1C6C4, gfx B $2440E, mask A $2C148, mask B
  $33E92. Init ($496/$4B6) copies mask word 0 over word 1 for $F01 groups from
  $2C150 and from $33E92.
- $6C4 swap: toggle $3D908; paused ($3D907) -> both screens draw from B tables.
- $794: every 6th call $7DC reads text $1AE50: $FF restart, 's' ($73) pause
  $A0 frames ($7B4 counter $3D902), ' ' nothing, else letter -> table entries
  23..25 of all four tables (A..F $1C6C4, G..L +$14A0, M..R, S..X, Y..^).
- Keys: F1/F2/F3 = $B6A/$B74/$B7E (part 1/2/3 into $3D90C, load), Space $A94 quits.
- Geometry (fit_geom.py / fit_rows*.py): capture x = screen pixel - 4, capture
  row = line + 1; open to capture x 411. Rows below line 256 (capture 258..262)
  are static: 15 star pixels (bottom_rows.py), drawn as measured.
- **Verified**: menu_model.py vs Hatari (frameskip 0): 1100 consecutive frames
  pixel-exact (cmp_menu.py, CAPDIR=m3, sync capture 1276 = model frame 0).
  The Zig port vs Hatari: apps/naos_nitrowave_headless.mjs, 12 frames exact.

## Oracle: the original code on Musashi

`m68loop.c` (Musashi from prototypes/snyd_re/tcb/m68, built with
`gcc -O2 -o m68loop m68loop.c m68/m68kcpu.c m68/m68kops.c m68/softfloat/softfloat.c -Im68 -lm`)
resumes a part's MAIN LOOP from a Hatari dump (registers from `DUMP.regs`,
written by `regs.py LOG VBL`), raises IRQ 4 at every `stop`, and saves RAM
after chosen VBLs. $FF8209 reads $10 so the fullscreen sync loops end.
`dump_part.sh N PC OUT VBL...` takes the dumps (pc + exact VBL breakpoints).
Without the registers the first VBL runs with a6 = 0 and scribbles: restore them.

## F2: BIGSPRITE + OVERSCAN (B_SPRITE.BIN at $800)

- Menu loader: F1 DEMO_RIC.BIN -> $800 ($6CC5 longs), F2 B_SPRITE.BIN -> $800
  ($5DC1 longs), F3 DAMIER3D.BIN -> $400. Each via $35000/$30000 then copied.
- Init: clears $17B66..top (bus error ends it); tile $107B6 (32x64) x7 a line
  from $6AE86 (= screen B $6AD00 + 160 + 230: line 1), x4 down, copied to screen
  A $5C200 and to the picture $4D700 (same layout). Sprite $10FB6 144x80
  (72 bytes a line), 15 preshifts $17BA2 + $1680k ($1E36: lsr/roxr a pixel),
  16 masks $2CD22 + $B40k (NOT OR of planes, the word twice).
- VBL $79800 generated from template $1558..$1DFE + fragments $5024..$10796
  (`frags2.py`), $1E82 packs them. Logical program (`bspr_prog.dis`):
  erase 80 lines x 72 bytes from $4D700 at the table *($1263A)'s offsets + 230i;
  draw 80 lines: a6 entries of 12 bytes (offset, gfx, mask): pos = offset +
  *(*($12A5A)), stored in the table; dst = *($12636) + pos + 230i;
  gfx + 72i, mask + 36i; 9 groups: both longs &= mask long, |= gfx longs.
  The palette $10796 is loaded at the top, $17B66 (black) after line 254.
- Main loop $1140 / $11BA (halves): music $1EFA, $1218 (a6: state 1 waits
  $12A62 frames, states 2..6 walk tables $12E32.. $135B2/$13972../$1416A../
  $1545A../$1697E.. with restart counts 8/4/1/4, state 7 to $1779A then $11FE
  restarts), $140C (*$12A5A: wait $12A5E frames, then step 4 bytes through
  $128C2..$12A52 ten times, wait $320...), screens: half A draws $5C200 with
  table $1277E and shows $6AD00; half B the other way. Key $21 'F' toggles
  freeze $17B86 (VBL still runs, no state moves); $1C/$39 (Return, Space)
  -> $1476: silence and reset (the disk boots the menu again).
- File values start the state machines ($12A64 = 1, $12A62 = 200, $12A60 = 1,
  $12A5E = 1000, $12A5A = $128BE -- one before the table).
- **Verified**: `bspr_model.py` from the FILE = Hatari RAM after 142 passes and
  = the oracle at 15 points to 8000 frames, every state (`bspr_check.py`);
  vs Hatari's capture (p2/, sync 2258) 1742 frames pixel-exact (`cmp_part.py`).
  Geometry as the menu (line L at capture row L+1, x+4); lines 0..254 shown.

## Music

Every program carries its own Mad Max TFMX replay + module (`tfmx.py` sizes the
module from its header; `rip_music.py` wraps replay+module as an SNDH via
`mk_sndh.py`; all play on the sealed YM). `ymscan.mjs` ranks the archive by
tone-period histogram, `ymcheck.sh` confirms aligned:

| program | rip | archive SNDH | aligned YM match |
|---|---|---|---|
| menu (TFMX $3C596, init d0=1) | menu_rip.sndh | Mad_Max/Demos/Cuddly_Demos/Big_Sprite.sndh #1 (~y) | 0.999 @ lag -2 |
| F1 DEMO_RIC | ric_rip.sndh | Mad_Max/Demos/Cuddly_Demos/Robocop_Tune_2.sndh #1 (~y) | 1.000 @ -2 |
| F2 B_SPRITE | bspr_rip.sndh | Mad_Max/Demos/So_Watt/So_Watt_No_Crew.sndh #1 (~y) | 1.000 @ -2 |
| F3 DAMIER3D (other replay build, header $676, tables hard-coded past the module) | dam_rip.sndh | AN_Cool/So_Watt-Techatron.sndh #1 | 0.999 @ -2 |

(The readme credits Mad Max for the menu, F1 and F2; F3's tune is AN Cool's.)
