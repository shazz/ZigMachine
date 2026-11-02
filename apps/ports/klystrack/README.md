# klystrack on the ZigMachine / KESTREL

[klystrack](https://github.com/kometbomb/klystrack) (Tero "kometbomb" Lindeman, MIT) is a chiptune tracker in C on
SDL2, built on his klystron engine (the `cyd` synth, `gfx`/`gui` on SDL_Renderer). Its minimum window is 320x240,
which fits the 400x280 overscan plane natively. Everything KESTREL-specific is here or in the shared SDL2 layer
`apps/ports/kestrel_sdl2`.

## Licence

`LICENSE` is upstream's (MIT, Tero Lindeman; additional graphics Ilija Melentijevic); klystron's sources carry
the same MIT text in their headers. The cart is built from klystrack `fe6e7465512bee32bf8e724857a7fbab902b8db0`
(10 May 2020) with klystron, its submodule, at `10743245fbaf67fc02b432577dc4d47ad5e459da`, both cloned untouched by
`../fetch.sh`. `data/` holds files generated from upstream (`make data`): the Default theme bundle and four example
songs. Ours (MIT, as the repo): every `kestrel_*` file, `mkbundle.py`, `patches/*.sed`, `Makefile`, `run.mjs`.

## Build

    apps/ports/fetch.sh
    make -C apps/ports/klystrack link             # build/demo-klystrack.wasm (byte-identical to docs/ at the pin)
    make -C apps/ports/klystrack install          # copy it to docs/, repack docs/demo-klystrack.zmd (tools/mkdisks.sh)
    node apps/ports_headless.mjs klystrack        # the gate's check: boot, UI pin, F5 plays STARPORT2.KT
    node apps/ports/klystrack/run.mjs 240         # from the repo root: headless run, PNGs in build/
    KEYS="30,57349" AUDIO=1 node ...run.mjs 240       # F5 (0xE005) at frame 30 = play; writes build/audio.wav
    CLICKS="30,270,87" node ...run.mjs 120            # click PLAY (klystrack 320x240 coordinates)

The cart: `docs/demo-klystrack.wasm` on `docs/demo-klystrack.zmd`.

## Layout

| file | what |
|---|---|
| `Makefile` | mirrors klystron (`gfx gui snd util`, not `lib/`) and klystrack (`src`, `src/import`, `src/view`, minus `midi.c`) into `build/gen/` (CRLF dropped, `patches/<file>.sed` applied: a patch must change its file), compiles with `zig cc -target wasm32-wasi`, links, runs binaryen 132's Asyncify (`../upstream/binaryen`, fetched by `../fetch.sh`); `make data` regenerates `data/` |
| `kestrel_main.c` | the cart's exports. klystrack's `main()` (renamed `klystrack_main` by `patches/main.c.sed`) runs as an Asyncify coroutine, as GrafX2: it yields in `SDL_Delay` and after every `SDL_RenderPresent`. `frame()` = clock + SDL timers, one VBL of audio, then resume. `argv[1]` = `STARPORT2.KT`, opened at boot |
| `kestrel_sdl.c` | what is klystrack-shaped: clock (1/60 s a VBL), fixed 320x240 window, the legacy `SDL_OpenAudio` device fed to the machine's stream |
| `kestrel_stubs.c` | `getpwuid` (no password database) |
| `kestrel_port.h` | force-included: the pattern / sequence caps, `getuid` |
| `mkbundle.py` | builds the `Default` theme bundle (klystron's `bnd!` format) like upstream's Makefile `theme_defs` |
| `patches/*.sed` | see below |
| `run.mjs` | headless runner (from pt2's): boots on `docs/machine-video.wasm` + `docs/rom.wasm` with the floppy, `CLICKS`, `KEYS`, `SNAP`, `AUDIO` |

### Patches (all small; each says why in its header)

| patch | change |
|---|---|
| `main.c.sed` | `main` -> `klystrack_main`; the song tables (`instrument`, `pattern`, `sequence`, `channel`) static instead of on the stack; no `midi_event`; render-to-texture off from the first `gfx_domain_update` (else a 300 KB texture leaks at boot) |
| `mused.h.sed` | `NUM_PATTERNS` 4096 -> 256, `NUM_SEQUENCES` 2048 -> 256 (upstream preallocates 2 MiB of pattern steps) |
| `music.c.sed` | refuse a song over those caps at load (upstream would write past the tables); `mus_set_fx` frees the reverb / chorus buffers of the buses a new song leaves off before applying it |
| `mused.c.sed` | default window 320x240, no "nostalgy" fake-decrunch intro, mix rate 22050 Hz |
| `cydrvb.c.sed`, `cydchr.c.sed`, `cydfx.c.sed` | the reverb delay line and chorus buffers of the 8 FX buses are allocated when a song first enables them, not at init (8 x 1.4 MB at 44.1 kHz); if the heap is short the effect stays off on that bus and the console says so |
| `menu.h.sed` | `struct menu_t {...} menu_t;` defined a variable in every file (needs `-fcommon`, which wasm clang crashes on) |
| `action.c.sed` | `current_pattern(NULL)` -> `current_pattern()`: wasm-ld turns an arity mismatch into a trap |

## The shared layer (apps/ports/kestrel_sdl2), what this port added

- `include/SDL2/SDL.h`: RWops, renderer info / targets / clip / fill / line / colour mod, `SDL_CreateTextureFromSurface`,
  `SDL_CreateSoftwareRenderer`, colour keys, `SDL_GetRGB`, `SDL_ConvertSurfaceFormat`, `SDL_BlitScaled`, timers,
  mutexes, `SDL_USEREVENT` + `SDL_UserEvent`, the legacy audio calls, `SDL_getenv`/`SDL_GetBasePath`/`SDL_GetKeyName`,
  and it now includes `SDL_endian.h` like the real one. `scancodes.inc` / `keycodes.inc` regenerated from SDL 2.30's
  headers (every existing value unchanged; adds `SDLK_EXCLAIM` etc.). New one-line headers `SDL_rwops.h`, `SDL_mutex.h`,
  `SDL_thread.h`. `SDL_image.h`: the NULL stubs stay the default; `-DKESTREL_SDL_IMAGE` declares the real ones.
- `src/opt/` (opt-in: a port's Makefile lists them; pt2 and GrafX2 do not, they define their own renderer stubs):
  - `kestrel_render.c`: software renderer. Surfaces are ARGB8888 or INDEX8; textures are 8-bit + palette when they
    have <= 256 colours (all theme art), else ARGB. Colour mod, NONE/BLEND/ADD/MOD, nearest scaling, clip, viewport.
    Cursors (`SDL_CreateColorCursor`) kept as ARGB for the presenter.
  - `kestrel_plane.c`: ARGB picture -> 8-bit plane (normal 320x200 or fullscreen 400x280, centred), palette rebuilt
    every present (more than 255 colours: extras take the nearest), the SDL cursor drawn at the mouse.
  - `kestrel_rwops.c` (stdio over the floppy, memory), `kestrel_timer.c` (timers fired from `frame()`, no-op mutexes),
    `kestrel_image.c` (`IMG_Load_RW` through stb_image; <= 256 colours -> INDEX8 surface), `kestrel_keyname.c`.
- `third_party/stb/stb_image.h`: v2.30, nothing/stb commit 013ac3b (2024-05-31), unmodified; see `VERSION` there.

## Status (1 Nov 2026)

- Builds from a clean tree: all 72 klystron + klystrack sources, no warnings that matter (K&R prototypes only).
  Imports only `env` (memory, consoleLogJS, diskReadBlock, hwVideoBase, hwRamAlloc, hwRamFree, hostAudioStreamStart,
  hostAudioFeed). Cart 556 KB after Asyncify (411 KB before), floppy 592 KB.
- Boots in ~60 ms headless into the classic editor with `STARPORT2.KT` loaded from the floppy; Default theme from the
  bundle (fonts, bevels, VU, cursor), mouse pointer drawn. F5 / clicking PLAY plays it: VU meters, follow-play,
  timer; `build/audio.wav` holds the fed stream (the machine's stream ring honours the 22050 Hz rate:
  `audioStreamStart` sets the Paula step from it). Ctrl+O opens klystrack's file dialog (an Asyncify'd modal
  loop), which lists the floppy's songs; each of the four, picked + OK, loads and plays with no trap (DPINTRO and
  Starport2 ask for more reverb/chorus buses than fit: those stay off, logged). ~2.5-2.9 ms a frame on average
  in node (worst ~17 ms, JIT warm-up).
- Floppy: `Default` (theme bundle, 10 KB), `STARPORT2.KT`, `CASTLEVANIA.KT`, `OCEANLOADER3.KT`, `DPINTRO.KT`
  (upstream examples, renamed to <= 16 characters).

### Memory (2 MiB window)

Statics + 128 KB stack + 64 KB Asyncify save area: 401 KB (0x100000-0x161D70). Heap arena 1,630,864 B; at boot with
Starport2 loaded, 1,595,376 B in use: one reverb (345 KiB) + one chorus (353 KiB) at 22.05 kHz, the 320x240 ARGB
render buffer (300 KiB), 256 patterns x 64 steps (134 KiB), theme surfaces/textures (~350 KB, of which 4 copies of
the 8x8 font: klystrack loads it once per Font). Starport2 enables reverb on a second bus, which does not fit and
stays off ("klystron: no memory for a reverb, left off").

With the 4 MiB window: 44.1 kHz with one reverb + one chorus needs ~2.3 MB of heap; every bus that enables reverb
adds 690 KB (chorus 707 KB) at 44.1 kHz, half that at 22.05 kHz. Then raise `mused.c.sed`'s mix rate.

## What's left

- In the browser, Ctrl+O / Ctrl+S are also browser shortcuts; whether the loader swallows them for a cart that
  `ownsKeyboard` is the host's business (headless they reach klystrack).
- Read-only floppy: saving songs/instruments/wavs fails (klystrack reports it); the config file is never written.
- The Themes and Keymaps menus list every file on the flat floppy (picking a song as a theme fails harmlessly).
- Pixel scale / fullscreen / window-size menu items are no-ops or wrong (the screen is fixed at 320x240 at scale 1).
- 22.05 kHz mixing and one reverb at most (memory, above). No MIDI.
- Songs with more than 256 patterns or sequence entries are refused (examples that save all 4096 patterns:
  AmsterdamBoppe, StarChips, dr.happy, smp_dingleberries_fix). Lazily allocated pattern steps would lift the cap.
- KESTREL board: not tried. cyd mixes in integers per sample, but panning/FX setup use float/double (soft-float on
  ZIGGY); the per-frame cost on the board is unmeasured.
- Registered (catalog, disk, `apps/ports_headless.mjs` in build.sh) on 2 Nov 2026.
