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
| `.../old_cart_sid.bin`, `player_test.zig`, `apps/harness/sidwizard_z_golden.mjs` | the C cart's first 4000 SID writes after F1 on FLASHBAK.SWM (the script regenerates them from `site/carts/demo-sidwizard.wasm`), and the test that the Zig-driven player writes the same |
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

## Cost (`node apps/harness/frame_cost.mjs site/carts/demo-sidwizard_z.wasm --bard --disk site/carts/demo-sidwizard_z.zmd`, an estimate)

Idle editor and playing Flash It Back alike: **0.74 Mc a frame**, of which the cart 0.03 Mc (the 6502 player's tick is ~600 6502 cycles, ~0.02 Mc a 60th) and FRESCO 0.7 Mc
(one plane); ~60 fps. The C cart's figure for the same screen is 1.7 Mc (apps/ports/sidwizard/README.md: it runs the editor's own 6502 code too). Not measured on the board yet.
The picture stores only what changed (a glyph cell, a sprite byte, the cursor's box); a frame with nothing new stores nothing.

## Differences to look for when comparing with the C cart

- The editor starts in **jam mode** as the C one does (Space switches to edit), but a jammed note makes **no sound here yet**.
- The SID's clock is exact PAL (a tick = 19656 cycles = 879.8 samples of the 44.1 kHz clock, 50.125 Hz); the C cart stamps by libcRSID's 714/16 cycles a 22.05 kHz sample (0.1 % off).
- The oscilloscope is a model of voice 3 from the SID registers (the real OSC3 is BARD's), no main-volume keys; the file dialog has the C editor's layout and colours in the repo's 8x8 system font (the C one's is the C64 character ROM).
- Follow-play: C= (Control) + F1 / F3, or the menu's AutoFollow; the pattern view then scrolls with the played row.
- The file dialog: Tab switches name / list, cursor-down moves 3, cursor-right 1 (Shift reverses), Return on `/C` enters C:, on `/NAME` a folder, on `/..` goes up; the floppy is read-only, a save from its root goes to C:\.
- Playing from the start sends a SID reset (an 8580, as the C cart's), the first writes are the C editor's own (the player's init and the adapter's instrument reset).

## Staging on the SD card (nothing is built for the board yet)

Board firmware first (the lock held, one build at a time): `cd fpga && make board-fw CART=sidwizard_z ZM_FPU=1 ZM_AUDIO=snd ZM_ZMX=1`
-> `fpga/build/hcycles/board_snd_fpu/sidwizard_z/fw.bin`; then `uv run python tools/glass_sd.py --out <dir> --fw-dir build/hcycles/board_snd_fpu --bit <bitstream>`.
It is a data disk (a GEM program, like NOTEPAD), so the card needs **two files**: `CARTS/tools/demo-sidwizard_z.zmd` (the disk as it is, `site/carts/demo-sidwizard_z.zmd`) and
`KESTREL/progs/demo-sidwizard_z/BOOT.WSM.zmd` (the same disk plus the board image), and `CARTS/shelf.txt` (the OSD's text) regenerated; read `MANIFEST.txt` for MISSING / STALE. The ROM, BARD and system
image are untouched by this cart (no new `system.rv32`). A stale `progs/demo-sidwizard_z/` from an earlier cart boots the old firmware (CartSilent): replace it whole.

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
- Jamming (a note key sounding in the editor; the C editor's `jamplay` needs more of its program than the player's block), instrument and config files (`.SWI`, `.CFG`), fast-forward, the mouse, themes beyond the
  menu's, markers play (F2 plays from the top), and editing a song while it plays (the player plays the image taken at F1).
- The cursor is a hollow box over the cell (the C64's sprite, placed by the cell, not the raster split's exact offset).
