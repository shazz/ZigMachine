# Nitrowave Demo (Naos, 1990) — RE notes

Demozoo 72475. Generation 4 competition (theme: the 3615 GEN4 minitel server).
Port: cart 81, `naos_nitrowave` (apps/zig/scenes/naos_nitrowave*.zig).

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
