# Nitrowave Demo (Naos, 1990) — RE notes

Demozoo 72475. Generation 4 competition (theme: the 3615 GEN4 minitel server).

## Sources

- `NITROWAV.ZIP` -> `NITROWAV.MSA` (the real disk). `msa2st.py` -> `NITROWAV.ST`,
  `fatx.py NITROWAV.ST disk` (BPB says 0 reserved sectors; FAT is really at
  sector 1, fatx.py patched). **Disk files are UNPACKED** -> use these.
- `NITRO_F.ZIP` = a later file/HD version: `NITRO.PRG` loader + LSD!-packed
  `*.BIN` (+ MENU.BIN as a PRG). Same content, packed. Not used.

Disk contents:

| file | size | what |
|---|---|---|
| AUTO/MENU.PRG | 252865 | BATTLETEC menu (Freddi; overscan by Aragorn; music Mad Max; gfx ATM). TEXT 50168, DATA 201848, BSS 158 |
| DEMO_RIC.BIN | 111376 | F1: MULTISPRITES (Ric) |
| B_SPRITE.BIN | 95078 | F2: BIGSPRITE + OVERSCAN (Aragorn) |
| DAMIER3D.BIN | 264526 | F3: SAPRISTI 3615 GEN 4 (Aragorn): overscan, checkerboards top+bottom, parallax, logo distort, scroller |
| LISEZ.MOI | | French readme (credits above) |

The .BIN parts are raw absolute-address images (no header), loaded by MENU.PRG
(`a:\demo_ric.bin`, `a:\b_sprite.bin`, `a:\damier3d.bin`).

## Music

Mad Max (Hippel) replay present in menu (TEXT+0x3bc19 sig), bspr (+0x1759),
ric (+0xe5d). DAMIER3D has no Mad Max signature (other player?).
See below for SNDH matches.
