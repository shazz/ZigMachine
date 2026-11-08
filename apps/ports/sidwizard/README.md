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
| SDL audio callback: `cRSID_generateSample()` per sample (the C64 is clocked by the audio) | `kestrel_audio_pump()` at 22,050 Hz: real time's worth of samples a frame, each one `cRSID_generateSample()` |
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
bars (every raster line's border colour), the main-volume bar and the disk light. The oscilloscope is drawn in
the header on the editor screen, as upstream. 16 text colours (pepto x the zoom-1 fade x 1.5) and 16 sprite
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
| envelopes once a sample (exact steps) | — | 10.0 |
| `-Os` | — | 8.7 |
| inlining not forced (91 KB emulate function -> 16 KB) | — | 7.7 |
| CIAs + VIC clocked at their next event or an I/O access | — | 6.3 |
| envelopes holding at sustain set no step limit | **5.2** | **5.9** |

So the C64 costs about **3.5x real time** on the board: the cart runs (~16-19 fps), but the C64 inside runs at
about 30 % speed: the audio ring gets about a third of real time's samples (`kestrel_audio.h`: it replays stale
bytes in between, as klystrack's did before BARD), and the song plays slow and broken (the frame is capped at 20
ms of C64 time: a slow board frame is not caught up, so the editor keeps answering). 50/60 fps does not hold.
In the browser it runs at full speed. The clock batching was checked by its results (the screens, the song
heard, the save byte-identical), not A/B'd sample for sample against upstream's per-instruction clocking. Where the rest goes: the
6502 core (`cRSID_emulateCPU`, ~0.84 Mc, ~165 cycles an instruction, ~5,100 instructions a frame: SID-Wizard's
main loop never idles), the instruction loop (0.34), the SID (light engine + envelopes ~0.5) and the I$ (2.7 Mc:
~21 KB of code a frame against a 16 KB cache). The two levers left: **the SID on BARD** (below: the SID render
and its code leave ZIGGY), and a smaller, faster 6502 core (docs/ROADMAP.md). No float runs a frame (upstream's
float is the PC display code, not built).

`kestrel_sw_clock.c` is where the clocking changed (CIAs and VIC handed their cycles at the next raster line, CIA
timer underflow or I/O access, exactly when upstream would have seen the event; envelopes in exact steps once a
sample); `patches/libcRSID__C64__*.sed` hook it in, and the key matrix is computed on a `$DC01` read only.

## The SID on BARD: one switch

`kestrel_sw_sid.h` `SW_SID_ON_BARD`: 0 (now) renders the SID here, from the C64's I/O page. 1 hands every write to
`$D400-$D7FF` to `sw_sid_write(register, value, C64 cycle)` after the instruction that wrote it (captured in the
I/O write path, `kestrel_sw_clock.c` `sw_io_write`), for a SID_WRITE command on the BARD message queue
(`feat/bard-queue`, not on main yet: building with 1 stops at an `#error` until then); the local render is then
to be skipped (the 6502 still reads `$D41B`/`$D41C` back). docs/ROADMAP.md has the row.

## Build

    make -C apps/ports/sidwizard link      # build/demo-sidwizard.wasm (zig cc, wasm32-wasi, -Os)
    make -C apps/ports/sidwizard names     # the same with function names, for apps/frame_cost.mjs
    make -C apps/ports/sidwizard install   # copy it to docs/ and repack the disk (tools/mkdisks.sh)
    make -C apps/ports/sidwizard data      # data/FLASHBAK.SWM from upstream's example
    node apps/ports/sidwizard/run.mjs 400  # headless: PNGs, KEYS=, CLICKS=, AUDIO=1, C_IMAGE= (see its header)

The cart is committed prebuilt (as every port: `./build.sh` does not rebuild it). Gates: `ports_sidwizard`
(`apps/ports_headless.mjs sidwizard`, `apps/sidwizard_save.mjs`).

## Provenance

| | |
|---|---|
| Upstream | SID-Wizard 1.97 PC version, `SID-Wizard-1.97-sources-examples.tar.gz` (md5 `a04e51857ebb783493df62db61dca430`), Hermit's 2026 release |
| `upstream/` | the files the cart uses, **unmodified**: `SIDwizard.c`/`.h` (read, not built: `kestrel_sw.c` is its port), `libcRSID/` (`libcRSID.c`, headers, `C64/`, `host/`), `host/` (`file.c`/`.h`, `keyboard.c`/`.h`, `mouse.c`, `buttoncharset.h`, `video_data.h` for reference, `KERNAL.asm`/`.bin`), `resources/` (`SID-Wizard.cmp`, `chargen`, the user manual), `native/sources/tools/` (Hermit's decompressor, run at build time by `tools/unpack.c`), `native/examples/flashitback.swm` ("HERMIT: FLASH IT BACK"), both READMEs |
| Why vendored | there is no repository to pin (other ports fetch theirs: `apps/ports/fetch.sh`), and the licence allows it |
| `patches/` | sed patches applied to a mirror in `build/gen/`, one per upstream path (`/` as `__`); a patch that changes nothing stops the build |
| Generated | `build/gen/resources/{SID-Wizard,KERNAL,chargen}.h` (`tools/bin2h.py`, as upstream's `bin2array`); the light engine's 22.05 kHz filter table is `libs/c/crsid/patches/SID_FilterCurves.h` (the two libraries' tables are the same file at 44.1 kHz) |
