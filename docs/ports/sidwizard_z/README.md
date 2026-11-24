# SID-WIZARD Z (cart 140, `sidwizard_z`)

SID-Wizard 1.97 by Mihaly "Hermit" Horvath (Hermit Software Hungary, with much help from Soci of Singular Crew), with its
**user interface in native Zig** and Hermit's **own 6502 player**, beside the existing C cart `sidwizard`
(`apps/ports/sidwizard`: the whole C64 program on an emulated 6502 + libcRSID), which is untouched, so the two can be compared on the board.

Licence: WTFPL ("Do what the frick you want with this code, but mentioning me if you use it would still be nice"), upstream
`README.txt`; Hermit is credited here, in `sdk/THIRD_PARTY.md` and in the cart's catalog line.

## Layout

| Where | What |
|---|---|
| `apps/zig/scenes/sidwizard_z.zig` | the cart (`App`): a GEM program, one overscan plane, input, the frame loop |
| `apps/zig/scenes/sidwizard_z/` swm, display, keys, menu, filer, startup, border, frame, editor `.zig` | the editor library (the Gemini port of `editor.asm` and its includes, `prototypes/swz_gemini/out`, parts 1-6): pure, no I/O, no allocator. Its own notes: `NOTES.md`, `STATUS.md` in this folder |
| `.../keymap.zig` `video.zig` `files.zig` `names.zig` `play.zig` `player.zig` `c64mem.zig` `sidout.zig` `session.zig` | the host: keys, the incremental picture, the floppy and C:, the 6502 player, the BARD queue, the effects |
| `.../sw_player.bin` | the player and playadapter code and variables cut out of SID-Wizard 1.97's editor program (`tools/sidwizard_z_player.py`; the 64tass build of `native/sources` equals `apps/ports/sidwizard/upstream/resources/SID-Wizard.cmp` unpacked, byte for byte) |
| `.../editor_charset.bin`, `sw_header.bin`, `vice_empty_*.bin` | SID-Wizard's own charset (a VICE dump of `$D000` while the editor runs), its header sprites, and four VICE dumps the library's tests compare against: all Hermit's, WTFPL |
| `.../old_cart_sid.bin`, `player_test.zig` | the C cart's first 4000 SID writes after F1 on FLASHBAK.SWM, and the test that the Zig-driven player writes the same |
| `apps/harness/sidwizard_z_check.mjs`, `sidwizard_z_lib.mjs` | the gate harness (`gate sidwizard_z` in `build.sh`) |

## The player path

The editor is Zig; the player stays 6502. `c64mem.zig` is a C64 as small as the player needs: 64 KiB of RAM, `libs/zig/players/cpu6502.zig` (the repo's
tested NMOS 6502 that runs the SAP players), the SID's registers as a write queue stamped with the 6502's cycle. `player.zig` does what the editor's
`playadapter.inc` / `keyhandler.inc` do around it: a fresh image (`swm.toC64` at MUSICDATA `$1DBB`), `inisub`, the adapter's `resetJamIns`
(the real `adapins` routine from the image), F3's pattern play, pause and continue; then `wCHDMOD` + `playsub` once a frame. `sidout.zig` puts
the writes on the BARD queue (`zg.bard`, table 1.12), stamped `base + cycle x 44100 / 985248` (the PAL C64's clock), paced by `bard.due`. Why this path: all
three pieces already existed and are tested (the 6502, the queue, the SID live on BARD); the alternative, libcRSID's 6502, is C and drags in a whole C64.

Proof: `player_test.zig` — the Zig-driven player's first 4000 SID writes after F1 are the C cart's, register for register and value for value
(needs `playmod`, the mute/solo bytes and the editor's start-up init state, all replicated); the gate harness repeats it end to end over the page's BARD.

## Deviations from the library as it came

- **D6, the image base.** The first port assumed the workfile at `$1D00`; the real editor build puts MUSICDATA at `$1DBB` and page-aligns the
  pattern and instrument areas in absolute space, so every offset after the headers moved (TEMPOTBL at `$A400`). `swm.music_data` and the two alignments
  are fixed; the player reads its tables there. The 8 swm tests, display, keys, menu, filer, startup, border, frame, editor tests still pass.
- `swm_test.zig` round-trips FLASHITBACK only (the other ten tunes are other composers' songs, not shipped).
- `frame.compose` clears with a memset (a `.{}` zero literal is a 112 KB blob in the cart); `Editor.reset()` builds the editor in place.
- Files over the 200-line rule, from the library as it came: `keys.zig` (3.7 k lines), `display.zig`, `swm.zig`, `menu.zig`, `filer.zig`. Not split here: a refactor of
  a byte-verified port is its own job (ROADMAP R87).

## What is not here yet

- The start-up menu (the player/tuning picker): the cart boots straight into the editor, so no C64 character ROM (Commodore's, never shipped) is needed. The file dialog and
  menus use SID-Wizard's own charset (`editor_charset.bin`); its capitals, digits and punctuation are all the dialog uses.
- Jamming (a note key sounding in the editor), instrument and config files (`.SWI`, `.CFG`), the oscilloscope (it needs the SID's OSC3, which is BARD's), fast-forward, the mouse, themes beyond the
  menu's, markers play (F2 plays from the top), and editing a song while it plays (the player plays the image taken at F1).
- The cursor is a hollow box over the cell (the C64's sprite, placed by the cell, not the raster split's exact offset).
