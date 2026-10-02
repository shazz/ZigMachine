# Dune — Gen4 Demo (1990-06-29) — RE notes (cart 82, tag dune_gen4)

Demozoo 178058. Credits per Demozoo: Music 520, Graphics Black Eagle, Code Hades.
Source: https://fujiology.org/ST/D/DUNE2/DUNEGEN4.ZIP (DUNEGEN4.MSA, 9 spt, 2 sides, 80 tracks).

## Disk
- `python3 msa2st.py DUNEGEN4.MSA DUNEGEN4.ST && python3 fatx.py DUNEGEN4.ST files`
- Plain FAT12 (media F9). Boot sector not executable. Volume label DUNE.BRU.
  DESKTOP.INF names drive A "DUNE" and drive B "3615 GEN4"; the demo is run from the desktop.
- Files: DUNE.PRG (32744, JEK-packed), MUSIQUE.PRG (6905), SINGSONG.PRG (16060), TETEDEAD.PRG (640),
  DUNE.TNY, INTRO.TNY, MENU.TNY, SOUND.TNY, ALPHA.DAT, BLACK.DAT, BLACKEAG.DAT, FONTE.DAT, FONTEH.DAT,
  XYEAGLE.DAT, SOUND2.SET (65704), ACCUEIL.MBS + GEN4.MBS (STOS banks, never named by DUNE.PRG),
  GEN4.DAT (0 bytes).

## DUNE.PRG = JEK Packer V1.3
- `python3 unjek.py files/DUNE.PRG dune_unpacked.prg` -> 71305 bytes, a GEMDOS PRG, TEXT $1148C,
  checksum residue 0. Stub transcribed from TEXT+$16C..$246; the stream is read backwards from the end
  of TEXT and runs below TEXT+$300 (output base), so the whole TEXT is input.
