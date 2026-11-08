# SID-Wizard 1.97 on the ZigMachine / KESTREL

[SID-Wizard](https://demozoo.org/productions/99999/), the C64 SID tracker by **Mihaly "Hermit" Horvath**
(Hermit Software Hungary, "with much help from Soci of Singular Crew"), as a cart: `docs/demo-sidwizard.wasm`
on its GEM data disk `docs/demo-sidwizard.zmd`, beside Hermit's example song "Flash It Back" (`FLASHBAK.SWM`,
which the cart opens at start). The 40x25 text screen is the C64's own, so it fits the machine's 320x200 (the
26th row and the header and orderlist sprites in the borders fit the 400x280 overscan plane).

Licence: WTF, upstream `README.txt`: "Do what the frick you want with this code, but mentioning me if you use it
would still be nice." Hermit is credited here, in the root `README.md`, `sdk/THIRD_PARTY.md` and the card's
`licenses/SID-Wizard-README.txt`.

## The approach: the PC version's design

SID-Wizard's PC version (SDL 1.2 / ncurses) does not reimplement the tracker: it runs the **native C64 program**
(`resources/SID-Wizard.cmp`, the 6502 code built from `native/sources`) on **its own libcRSID**, which, unlike the
plain .sid player (`libs/c/crsid`, cRSID 1.58), has the C64 it needs: the 6502 with real CIA and VIC raster IRQs,
the keyboard matrix, the VIC bookkeeping a display needs (`VIC.h`: which screen bank and charset each raster
line sees), and the KERNAL traps for disk I/O (`host/KERNAL.bin` posts OPEN/LOAD/SAVE/CHRIN/CHROUT/CHDIR to
zero page `$F6..`, `host/file.c` serves them with stdio). The cart does the same; only the host is ours:

| upstream (PC) | here |
|---|---|
| `SIDwizard.c` `main()`: set-up, the 5 ms main loop (SDL events, `getKeyStates`, the command-line file's key simulator, `handleDiskIO`), `displayScreen` every 20 ms | `kestrel_sw.c` (set-up, `boot`/`frame`, the main-loop pass `sw_tick` every 110 samples = 5 ms), `kestrel_sw_keysim.c` (the key simulator, ported as it is: it opens `FLASHBAK.SWM` at start) |
| SDL audio callback: `cRSID_generateSample()` per sample (the C64 is clocked by the audio) | the frame's real time worth of 22,050 Hz C64 steps (`cRSID_emulateC64()`), the SID's writes on the BARD queue ("The SID on BARD"); with `SW_SID_ON_BARD 0`, `kestrel_audio_pump()` as upstream |
| `host/video*.c`: 32-bit SDL surfaces, zoom, scanline fade, blur | `kestrel_sw_video.c` + `kestrel_sw_draw.c`: the **C64-UI mode at zoom 1** as palette indices straight into the 400x280 plane, only what changed (cells, sprite bytes, raster-bar rows); upstream's "lofiborder" (no sprite blur) |
| `host/keyboard.c`, `keyboard.h`, `mouse.c` | **unchanged**, over `include/SDL.h` (SDL 1.2 key symbols + `SDL_GetKeyState()`), which `kestrel_sw_keys.c` fills from the cart's `key`/`keyUp`/`input`/`pointer` exports |
| `host/file.c` over the PC's file system | **unchanged** but for `patches/host__file.c.sed`, over wasi-libc: the floppy (read-only) and C: as `/C` (KOS GEMDOS) |

Why not a SDL 1.2-on-SDL2 shim: the display code is the PC's SDL surfaces at 32 bits, zoomed and float-faded,
and converting that to the 8-bit plane every frame costs more than drawing the C64 screen as indices; the rest
of SDL 1.2 that SID-Wizard uses is a key-state array. So: the C64 and its program unchanged, upstream's
keyboard/mouse/disk code unchanged, a small host for the picture, sound and keys.

### Picture

The C64 picture is 340x254 at (30,13) of the plane: a 10-pixel left border (black: upstream's zoom / SID model /
MIDI buttons are not here), the header sprites (7, x-expanded) on top, 26 text rows (row 26 is SID-Wizard's VIC
trick: another screen bank from raster line `$F7`), the orderlist sprites below, and on the right the raster
bars (every raster line's border colour), the main-volume bar and the disk light. The oscilloscope (upstream draws it
in the header on the editor screen) is drawn only with the SID here (`SW_SID_ON_BARD 0`). 16 text colours (pepto x the zoom-1 fade x 1.5) and 16 sprite
colours (pepto x 1.5).

### Keys

Upstream's C64 key map (manual: "CONTROL is Tab, C= is Control, RUN-STOP is Esc, ` (back-arrow)", the piano keys
by position). The machine's key ABI had no Tab, Home, End, PageUp or PageDown, which SID-Wizard needs (Tab steps
tracks, switches the file dialog's fields): they were added as **owner-only codes** 0xE019..0xE01D
(`docs/sealed-loader.js` `OWNER_KEY_CODES`, the board glass's `map.zig` and firmware `glass_input.c`; decisions.md
2026-11-07), sent only to a cart that owns the keyboard. Upstream's PC-side keys: Shift+F8 the exit dialog (Y
quits back to GEM), Shift+F7 / Shift+F9 reset the editor, Shift+Up/Down the main volume (upstream's F11/F12 too,
but the machine sends no code for them: the board keeps them for its OSD). A click positions the cursor as upstream's mouse code does (the left
border's buttons are not drawn). No MIDI.

### Files

Device 8 starts in the floppy's root: the load dialog (F8, LOAD TUNE) lists `FLASHBAK.SWM`. The floppy is
read-only; **songs are saved on C:** (the SD card's `/HD`, the page's `?c=` image): the floppy's root lists C: as
the folder `C` (Tab, Tab to the selector, Return), and C:'s root a `..` back; device 9 is C: too.
`patches/host__file.c.sed` and `kestrel_sw_files.c`: the folders, a file open that refuses the flat floppy's
pseudo-folders (`@swconfig` is not there), `..` taken off the path by hand, and the extension filter case-blind
(FAT names are upper case). `apps/sidwizard_save.mjs` saves the opened song to `C:\MYSONG.SWM` and reads it back
byte for byte.

## Cost (`apps/frame_cost.mjs`, est. on ZIGGY at 100 MHz)

| build | idle editor | playing Flash It Back |
|---|---|---|
| upstream as it is (always-inline, -O2, every part clocked every 6502 instruction) | — | 11.6 Mc/frame |
| envelopes once a sample, `-Os`, inlining not forced, CIAs + VIC at their events (port/sidwizard) | 5.2 | 5.9 |
| the SID on BARD (feat/sidwizard-bard): no SID render, no envelopes here | 3.7 | 3.7 |
| and the picture stores only what changed (VRAM 9 KB -> 1.9 KB a frame, same pixels frame for frame) | 3.9 | 3.9 |

(The last row is the same within the estimate's noise: the stores are cheap since posted stores; it is FRESCO's
dirty-line planner that gains, 20 of 280 lines changing a frame. The board's "296 %" was the whole frame, cart +
FRESCO, against a 60th: `budget.zig percent`, not FRESCO alone.) What is left is the 6502: `cRSID_emulateCPU`
~0.8 Mc, ~5,100 instructions a 60th (the editor's main loop never idles), the instruction loop 0.3, the CIAs/VIC
hand-overs 0.3, and the I$ (1.4 Mc: ~19 KB of code a frame for a 16 KB cache): ~2.3x real time, which is why the
main program yields to the IRQs on the board (above). A smaller, faster 6502 core is the lever left (ROADMAP).

`kestrel_sw_clock.c` is where the clocking changed (CIAs and VIC handed their cycles at the next raster line, CIA
timer underflow or I/O access, exactly when upstream would have seen the event; envelopes in exact steps once a
sample when the SID is here); `patches/libcRSID__C64__*.sed` hook it in, and the key matrix is computed on a
`$DC01` read only.

## The SID on BARD (decisions.md 2026-11-08)

`kestrel_sw_sid.h` `SW_SID_ON_BARD` is 1: the cart renders no SID. Every write the 6502 makes to `$D400-$D7FF`
goes on the BARD queue (`kestrel_sw_bard.c`, a C copy of `libs/zig/bard.zig`'s ring, `hostBardAttach`) after the
instruction that made it, stamped with its C64 cycle on the cart's 44.1 kHz clock (`t = cycle x 32 /
SampleClockRatio`); SID live plays it on BARD (on the page: the worklet; natively: `host/audio_bardq.c`), a lead
(~139 ms) behind. A reset and the registers as the C64 holds them open the queue at t 0.

- **The clock:** the C64 runs on the frame's real time (`kestrel_frame_us`, capped at 100 ms), no longer on the
  audio, so the player's IRQs, and the song's tempo, follow real time at any frame rate.
- **When ZIGGY can't run all of it** (`kestrel_sw_pace.c`): each frame the emulation may take 85 % of the time it
  covers; past that (never in the frame's first tenth) only IRQ handlers run and the main program waits until the
  next frame. The IRQs (~40 % of the C64's time: player, raster splits) keep their time; the editor slows.
  Without a host clock (the harnesses) nothing waits.
- Lost with it: the header's oscilloscope (the samples are BARD's) and the main-volume keys.
- `SW_SID_ON_BARD 0` builds the old way (the light engine here, the audio as the clock) to measure against.

Proofs: `apps/sidwizard_bard_check.mjs` (page = native host, 14.8 s from the first heard sample; tempo: 20 ms and 60
ms frames make the same writes with the same stamps and the same samples; hold: with the main program held 2/3 of
every frame the song's ticks are the same writes at the same distances; `--break stamp|reg` caught), and
`apps/ports_headless.mjs sidwizard` hears the song on the page's SID live. `--dump <file>` writes the song's
commands for `make snd-bench SND_BARDQ=1 BARDQ_LOG=<file>` (BARD's load: not measured yet; the engine is BARD
SID's, 58 %).

## Build

    make -C apps/ports/sidwizard link      # build/demo-sidwizard.wasm (zig cc, wasm32-wasi, -Os)
    make -C apps/ports/sidwizard names     # the same with function names, for apps/frame_cost.mjs
    make -C apps/ports/sidwizard install   # copy it to docs/ and repack the disk (tools/mkdisks.sh)
    make -C apps/ports/sidwizard data      # data/FLASHBAK.SWM from upstream's example
    node apps/ports/sidwizard/run.mjs 400  # headless: PNGs, KEYS=, CLICKS=, AUDIO=1, C_IMAGE= (see its header)

The cart is committed prebuilt (as every port: `./build.sh` does not rebuild it). Gates: `ports_sidwizard`
(`apps/ports_headless.mjs sidwizard`, `apps/sidwizard_save.mjs`, `apps/sidwizard_bard_check.mjs`).

## Provenance

| | |
|---|---|
| Upstream | SID-Wizard 1.97 PC version, `SID-Wizard-1.97-sources-examples.tar.gz` (md5 `a04e51857ebb783493df62db61dca430`), Hermit's 2026 release |
| `upstream/` | the files the cart uses, **unmodified**: `SIDwizard.c`/`.h` (read, not built: `kestrel_sw.c` is its port), `libcRSID/` (`libcRSID.c`, headers, `C64/`, `host/`), `host/` (`file.c`/`.h`, `keyboard.c`/`.h`, `mouse.c`, `buttoncharset.h`, `video_data.h` for reference, `KERNAL.asm`/`.bin`), `resources/` (`SID-Wizard.cmp`, `chargen`, the user manual), `native/sources/tools/` (Hermit's decompressor, run at build time by `tools/unpack.c`), `native/examples/flashitback.swm` ("HERMIT: FLASH IT BACK"), both READMEs |
| Why vendored | there is no repository to pin (other ports fetch theirs: `apps/ports/fetch.sh`), and the licence allows it |
| `patches/` | sed patches applied to a mirror in `build/gen/`, one per upstream path (`/` as `__`); a patch that changes nothing stops the build |
| Generated | `build/gen/resources/{SID-Wizard,KERNAL,chargen}.h` (`tools/bin2h.py`, as upstream's `bin2array`); the light engine's 22.05 kHz filter table is `libs/c/crsid/patches/SID_FilterCurves.h` (the two libraries' tables are the same file at 44.1 kHz) |
