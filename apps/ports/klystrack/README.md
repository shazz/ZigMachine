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
    node apps/ports_headless.mjs klystrack        # the gate's check: boot, UI pin, F5 plays STARPRT2.KT, Esc quits to GEM
    node apps/klystrack_cost.mjs                  # the gate's repaint-cost ceilings (frame_cost est, playing and menu)
    node apps/ports/klystrack/run.mjs 240         # from the repo root: headless run, PNGs in build/
    KEYS="30,57349" AUDIO=1 node ...run.mjs 240       # F5 (0xE005) at frame 30 = play; writes build/audio.wav
    CLICKS="30,270,87" node ...run.mjs 120            # click PLAY (klystrack 320x240 coordinates)
    CART=other.wasm node ...run.mjs 240               # the same run on another build (before/after)
    make -C apps/ports/klystrack names            # build/names/demo-klystrack.wasm: the cart with function names
    node apps/frame_cost.mjs apps/ports/klystrack/build/names/demo-klystrack.wasm --disk docs/demo-klystrack.zmd
                                                  # board cost per frame; add --call 30:key:57349 --call 33:keyUp:57349
                                                  # to play (F5), or --warmup 0 --frames 1 for boot()

The cart: `docs/demo-klystrack.wasm` on `docs/demo-klystrack.zmd`.

## Layout

| file | what |
|---|---|
| `Makefile` | mirrors klystron (`gfx gui snd util`, not `lib/`) and klystrack (`src`, `src/import`, `src/view`, minus `midi.c`) into `build/gen/` (CRLF dropped, `patches/<file>.sed` applied: a patch must change its file), compiles with `zig cc -target wasm32-wasi`, links (with function names), runs binaryen 132's Asyncify (`../upstream/binaryen`, fetched by `../fetch.sh`) with `asyncify_leaves.py`'s removelist, strips the names; `make data` regenerates `data/` |
| `asyncify_leaves.py` | lists the functions that can never be on the stack when `kestrel_yield` unwinds (an indirect call resolved by its type) for Asyncify's removelist: 751 of 892 are left uninstrumented (below) |
| `kestrel_main.c` | the cart's exports. klystrack's `main()` (renamed `klystrack_main` by `patches/main.c.sed`) runs as an Asyncify coroutine, as GrafX2: it yields in `SDL_Delay` and after every `SDL_RenderPresent`. `frame()` = clock + SDL timers, the frame's real time of audio (`kestrel_audio.h`: hostMicros, else dt; at most 2 frames' worth), a queued key/click wakes the repaints, then resume; a frame that presented nothing moves the pointer alone (`kestrel_plane_cursor`). `argv[1]` = `STARPRT2.KT`, opened at boot; when `klystrack_main` returns (Esc), `kestrel_quit()`: back to GEM |
| `kestrel_sdl.c` | what is klystrack-shaped: clock (the frame's real time), fixed 320x240 window, the legacy `SDL_OpenAudio` device fed to the machine's stream. **Quiet synth:** no song, every channel's gate off and envelope 0, and 2.2 s of exact silence (longer than the reverb's 2 s line, no feedback): cyd is not called, zeros are fed, until a note or a song starts. **Repaints:** `kestrel_redraw_due` (below) |
| `kestrel_chorus.c`, `kestrel_sine.h` | klystron's chorus LUT (`cydchr_set`) in integers: a Q30 sine table (generated, 1024 steps, interpolated), the phase stepped exactly, one 32x32->64 multiply. Within +-1/256 sample of upstream's double `sin()`; 7 of 151,404 stream bytes differ by 1 LSB over a 7 s play |
| `kestrel_stubs.c` | `getpwuid` (no password database) |
| `kestrel_view.c`, `kestrel_view.h`, `kestrel_views.c` | round 4: a view (or a block of one) skipped on an event-free repaint when nothing it reads changed; which views, and what each reads (below) |
| `kestrel_pattern.c`, `kestrel_rows.c` | round 4: the pattern view's step counter and rows as blocks, its VU meters after them; the rows scrolled in per-channel caches |
| `hashes.sh`, `vu_proof.mjs` | the "same pixels" proofs: every frame hashed in 11 scenarios for two carts; the VU meters' part (three carts in lockstep) |
| `kestrel_printf.c`, `printf_test.c` | the labels' vsnprintf: %s %c %d %i %u %x %X %% with - 0 + space, a width, a %s precision; anything else is musl's whole. `make printf-test` (gated) checks it against the host C library (glibc; the board's fallback is musl, which agrees on these conversions) |
| `kestrel_port.h` | force-included: the pattern / sequence caps, `getuid` |
| `mkbundle.py` | builds the `Default` theme bundle (klystron's `bnd!` format) like upstream's Makefile `theme_defs` |
| `patches/*.sed` | see below |
| `run.mjs` | headless runner (from pt2's): boots on `docs/machine-video.wasm` + `docs/rom.wasm` with the floppy, `CLICKS` (`frame,x,y[,buttons,hold]`: 4 = right button), `MOVES` (`frame,x,y,buttons`), `KEYS`, `SNAP`, `AUDIO`, `HASHES=file` (sha256 of every frame's picture: `CART=old.wasm HASHES=a.txt` then `HASHES=b.txt`, `cmp`) |

### Patches (all small; each says why in its header)

| patch | change |
|---|---|
| `main.c.sed` | `main` -> `klystrack_main`; the song tables (`instrument`, `pattern`, `sequence`, `channel`) static instead of on the stack; no `midi_event`; render-to-texture off from the first `gfx_domain_update` (else a 300 KB texture leaks at boot); the 30 Hz repaint only while something moves (`kestrel_redraw_due`: a song plays, one of the last 15 repaints changed the picture, an SDL timer fired, a key/click/drag was queued); events and song-position changes repaint at once as upstream |
| `msgbox.c.sed`, `help.c.sed`, `hubdialog.c.sed` | the same repaint rule in the dialogs' own loops |
| `mused.h.sed` | `NUM_PATTERNS` 4096 -> 256, `NUM_SEQUENCES` 2048 -> 256 (upstream preallocates 2 MiB of pattern steps) |
| `music.c.sed` | refuse a song over those caps at load (upstream would write past the tables); `mus_set_fx` frees the reverb / chorus buffers of the buses a new song leaves off before applying it |
| `mused.c.sed` | default window 320x240, no "nostalgy" fake-decrunch intro, mix rate 22050 Hz |
| `cyd.c.sed` | no oversampling (upstream's 4x won over the config); channels nobody hears (gate off, no ring-mod listener: one mask a sample, not a scan of every channel per channel) skip their oscillator and wavetable reads but still advance; an FX bus with no effect is passed through without `cydfx_output` |
| `cydrvb.c.sed` (also) | a tap keeps its delay in samples and reads at write position minus delay: the same sample without 16 tap increments a sample |
| `cydchr.c.sed` (also) | the chorus LUT from `kestrel_chorus.c` instead of a double `sin()` an entry (88,200 entries: ~630 Mc, 6 s on the board, at every load of a song with a chorus) |
| `cydrvb.c.sed`, `cydchr.c.sed`, `cydfx.c.sed` | the reverb delay line and chorus buffers of the 8 FX buses are allocated when a song first enables them, not at init (8 x 1.4 MB at 44.1 kHz); if the heap is short the effect stays off on that bus and the console says so |
| `bevel.c.sed` | `bevelex` drawn as one group (`kestrel_group_begin`): an unchanged bevel reuses last frame's tile copies |
| `font.c.sed` | `inner_write` drawn as one group (its cursor/bounds the outputs); a space keeps a NOP entry; `font_write_va` formats with `kestrel_vsnprintf` |
| `menu.h.sed` | `struct menu_t {...} menu_t;` defined a variable in every file (needs `-fcommon`, which wasm clang crashes on) |
| `action.c.sed` | `current_pattern(NULL)` -> `current_pattern()`: wasm-ld turns an arity mismatch into a trap |
| `view.c.sed` | round 4: `my_draw_view` runs each view through `kestrel_views.c` (klystron's own `gui/view.c`, same file name, gets a comment only) |
| `pattern.c.sed` | round 4: the rows block, the VU meters drawn after it, the rows loop run once a cache pass (`kestrel_rows.c`), the step counter a block |

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
    An indexed texture blits through one palette read a pixel (scaled or not), its colour mod applied once to the
    palette (cached until the mod changes) rather than three divides a pixel.
    Cursors (`SDL_CreateColorCursor`) kept as ARGB for the presenter. The WINDOW target is 8-bit (perf/klystrack-ui):
  - `kestrel_window8.c`: the window drawn as palette indices; a texture copy maps texture index -> window index
    (cached per texture and colour mod), blends read the destination's colour from the palette.
  - `kestrel_palette.c`: ARGB -> index, one palette kept across presents (index 0 black), compacted (the indices
    still used renumbered in both buffers) when all 256 are taken; a picture of more than 255 colours draws the
    extras as the nearest entry.
  - `kestrel_defer.c` / `kestrel_defer_draw.c` / `kestrel_defer.h`: the window's copy/fill/clear/line RECORDED
    in one list rewritten in place (command i compared with entry i, last frame's; stored only when it differs;
    a call that draws nothing keeps a NOP entry), and replayed at the present only into the 16x8 tiles a
    differing (or blending) command touches. 4,096 entries (224 KB) + a 64 KB group arena at the end of the
    largest free block, let go when a malloc fails (`-DKESTREL_HEAP_PRESSURE`: a song's reverb/chorus wins).
  - `kestrel_defer_group.c`: GROUPS (`kestrel_group_begin/end`, called by `patches/bevel.c.sed` and
    `font.c.sed`): a bevel or a string whose key (area/offset/flags, or font/rect/cursor/bounds/bytes, plus the
    renderer's viewport and clip and the texture's serial/mod/blend) equals last frame's at that entry keeps
    its entries and outputs, and klystron's loop is not run; a group missing where entries were dropped looks
    up to 256 entries ahead and moves last frame's rest down to it.
  - `kestrel_render_priv.h`: what these share (the texture struct, the blend, the module calls).
  - `kestrel_plane.c`: the window's indices -> 8-bit plane (normal 320x200 or fullscreen 400x280, centred):
    compared with the last picture shown a word at a time in the bands the replay drew, only differing words
    stored, only new palette entries written; the SDL cursor drawn at the mouse, put back from that copy.
  - `kestrel_rwops.c` (stdio over the floppy, memory), `kestrel_timer.c` (timers fired from `frame()`, no-op mutexes),
    `kestrel_image.c` (`IMG_Load_RW` through stb_image; <= 256 colours -> INDEX8 surface), `kestrel_keyname.c`.
- perf/klystrack-board: `kestrel_plane.c` hashes each presented picture (`kestrel_plane_changed`) and can move the
  pointer over the last picture without a present (`kestrel_plane_cursor`); `kestrel_render.c` turns an INDEX8
  surface into a texture with one hash per surface colour (not per pixel), copies unscaled indexed art without the
  16.16 stepping and divides; `kestrel_image.c` hashes an image's pixels once (not twice); `kestrel_timer.c` counts
  the callbacks it ran (`kestrel_timers_fired`). `src/kestrel_heap.c` (all four ports) gains an opt-in first-fit
  rover, `-DKESTREL_HEAP_ROVER` (klystrack only: the same block chosen, the scan starts past the used ones; the other
  ports build byte-identical without it).
- `third_party/stb/stb_image.h`: v2.30, nothing/stb commit 013ac3b (2024-05-31), unmodified; see `VERSION` there.

## Status (1 Nov 2026)

- Builds from a clean tree: all 72 klystron + klystrack sources, no warnings that matter (K&R prototypes only).
  Imports only `env` (memory, consoleLogJS, diskReadBlock, hwVideoBase, hwRamAlloc, hwRamFree, hostAudioStreamStart,
  hostAudioFeed). Cart 566 KB after Asyncify; floppy 241 KB (2 Nov: the cart ZX0-packed, the SDL boot sector, 5 files).
- Boots in ~60 ms headless into the classic editor with `STARPRT2.KT` loaded from the floppy; Default theme from the
  bundle (fonts, bevels, VU, cursor), mouse pointer drawn. F5 / clicking PLAY plays it: VU meters, follow-play,
  timer; `build/audio.wav` holds the fed stream (the machine's stream ring honours the 22050 Hz rate:
  `audioStreamStart` sets the Paula step from it). Ctrl+O opens klystrack's file dialog (an Asyncify'd modal
  loop), which lists the floppy's songs; each of the four, picked + OK, loads and plays with no trap (DPINTRO and
  Starport2 ask for more reverb/chorus buses than fit: those stay off, logged). ~2.5-2.9 ms a frame on average
  in node (worst ~17 ms, JIT warm-up).
- Floppy (a GEM data disk: GEM lists `BOOT.WSM`, the program, beside these; a double-click runs it, Esc quits back to
  the desktop, `../README.md`): `Default` (theme bundle, 10 KB), `STARPRT2.KT`, `CASTLEVA.KT`, `OCEANLD3.KT`, `DPINTRO.KT`
  (upstream examples, `data/` keeps the long names; the disk gives them 8.3 ones, tools/mkdisks.sh).

### Memory (2 MiB window)

Statics + 128 KB stack + 64 KB Asyncify save area: 401 KB (0x100000-0x161D70). Heap arena 1,630,864 B; at boot with
Starport2 loaded, 1,595,376 B in use: one reverb (345 KiB) + one chorus (353 KiB) at 22.05 kHz, the 320x240 ARGB
render buffer (300 KiB), 256 patterns x 64 steps (134 KiB), theme surfaces/textures (~350 KB, of which 4 copies of
the 8x8 font: klystrack loads it once per Font). Starport2 enables reverb on a second bus, which does not fit and
stays off ("klystron: no memory for a reverb, left off").

With the 4 MiB window: 44.1 kHz with one reverb + one chorus needs ~2.3 MB of heap; every bus that enables reverb
adds 690 KB (chorus 707 KB) at 44.1 kHz, half that at 22.05 kHz. Then raise `mused.c.sed`'s mix rate.

## Playing on the machine's .kt player (3 Nov 2026)

Play (F5, the PLAY button, play from the cursor) hands the song to the machine's `.kt` player
(`libs/zig/players/kt.zig`: BARD on the board, the audio thread in the browser) instead of mixing it
with cyd on the cart CPU (`kestrel_bard.c`): the song is written as a .kt (`save_song_inner`, its
"save unused elements?" question skipped: `patches/diskop.c.sed`) and passed with `requestSongBytes`
(kind 5) from the row Play started at; cyd's stream stops and cyd keeps only its sequencer, so the
position, the pattern view and follow-play move as before, on the real-time clock (the 33 ms cap is
lifted while the machine plays). An edit while it plays is caught by a hash of the song every quarter
second of song time and re-sent from the row playing (the voices restart there). Stop asks for
"none" and cyd takes the stream back. A song the player would refuse (more than 16 channels, over
256 KiB, over its song RAM) stays on cyd. The machine's player has room for every reverb bus a song
enables (cyd here keeps one). Keyjazz while a handed-over song plays is silent.
`make EXTRA=-DKESTREL_NO_BARD` builds the cart with cyd as before.

`apps/frame_cost.mjs` while playing STARPRT2.KT (est Mc a frame, frames 121-180): 34.1 with cyd ->
23.8 with the hand-over (cart 9.6 -> 5.3, I$ misses 23.8 -> 17.9): the rest is the UI's 30 Hz repaint
(SDL_RenderCopy / RenderPresent / colour_index), the next lever.

## The UI repaint (perf/klystrack-ui, 3 Nov 2026)

Matt's board: 5 fps while a song plays, and also with the song stopped while a menu is open: any full repaint.
klystron redraws its whole UI on every repaint (30 a second while a song plays, every event while a menu is
open), and on the board once a frame takes longer than 33 ms the 30 Hz tick is due every frame, so the fps is
~100 / (Mc of one repaint). `apps/frame_cost.mjs`, est Mc (STARPRT2 playing: frames 121-180; menu: the right
button held, the pointer moving every frame, frames 166-225, every frame a repaint; the worst case):

| | before (main 14dcbbe1) | after |
|---|---|---|
| a repaint while playing, median / worst (row scroll) | 41.2 / 46.0 | **10.6 / 21.5** |
| playing, average a frame (repaint every other frame here: frame_cost's fixed dt) | 23.8 | **7.4** |
| menu open, pointer moving (a repaint a frame) | 37.2 | **8.1** |
| idle | 1.21 | 1.19 |

Where a repaint went (before): the renderer drew ARGB, then the presenter turned every pixel back into an index
(`colour_index`) and rewrote the whole plane and palette; and binaryen's Asyncify had instrumented the pixel
loops themselves (it assumes any indirect call may unwind, and malloc and printf make one), so they tested the
unwind state per pixel. ~2,500 draw calls a repaint (glyphs ~1/3, bevel pieces, buttons). The I$ term is ~70 % of
the estimate (a repaint runs 32-45 KB of code), so instructions are what count. Step by step (playing / menu):

| step | playing | menu |
|---|---|---|
| window drawn as 8-bit indices, one palette kept, present stores only changed words | 23.8 -> 21.2 | 37.2 -> 33.4 |
| Asyncify only where it can unwind (`asyncify_leaves.py`, `-asyncify-ignore-imports`) | -> 14.1 | -> 21.8 |
| drawing recorded, replayed only in tiles that differ from last frame (`kestrel_defer.c`) | -> 8.1 | -> 9.0 |
| `USESTATICTEMPSTRINGS` (klystron's own option: one vsnprintf a label, no malloc), packed commands | -> 7.4 | -> 8.1 |

What a repaint costs now (~3 M rv32 instructions): recording ~2,500 calls (~400 instructions each: SDL_RenderCopy
+ the compare), the replay of what changed (most on a row scroll), printf for the labels, klystron's widgets,
the present. Next levers, in order: fewer calls (a text-run command from a font.c patch: one per string, not per
glyph; bevels as one command), a vsnprintf subset that hands anything unusual to musl, `song_hash` (kestrel_bard.c,
~1 M instructions every quarter second of song time) made incremental. The board decides; the model over-charged
the old pixel loops (41 est for a ~20 Mc board repaint), the remaining code is less loop-shaped.

The same pixels: `run.mjs HASHES=` in six scenarios (idle, playing, menu with the pointer moving, Ctrl+O file
dialog, quit, File > Open song from the menu) gives the same frame hashes at every step, and the gate's UI pin is
unchanged. Against main, two differences, both in the old presenter: (a) the picture's row 0 while the menu bar
is open (and under the dialog opened from it) was black: its run cache started at `~0u`, which is opaque white,
so white pixels at the start of the picture took index 0 (now white, as drawn); (b) every playing picture holds
more than 255 colours (the VU meter is a 32x64 ARGB gradient, drawn twice), so both presenters map the extras to
the nearest entry, in a different order: 5,298 physical pixels of the VU area at frame 60 differ, by at most 47
a channel.

Memory: the cart 584 -> 436 KB (Asyncify instruments 141 functions, not most); the window buffer 300 -> 77 KB;
the command lists +346 KB (heap in use at boot 1.95 -> 1.72 MB, 2.06 MB once the lists are taken at the first
present). Loading DPINTRO, whose chorus no longer fit, makes the lists let go (the window then draws at once)
and the chorus is allocated as before; they come back when 600 KB are free again. No upstream patch changed.

## Round 2 (perf/klystrack-ui-2, 4 Nov 2026)

Round 1 on the board: playing 11-13 fps (cart 6.3-8.9 Mc), idle 60. A repaint still made ~2,500 draw calls
(~400 rv32 instructions each to record and compare), though nearly all drew what they drew the frame before.
`apps/klystrack_cost.mjs` (frame_cost est Mc, same windows as round 1):

| | round 1 | round 2 |
|---|---|---|
| a repaint while playing, median | 10.6 | **5.9** |
| a repaint on a row change (worst) | 21.5 | **14.3** |
| the repaint after a row change | ~11.8 | ~6 |
| menu open, pointer moving (a repaint a frame) | 8.1 | **3.9** |
| playing, average a frame (frame_cost's fixed dt) | 7.4 | 4.4 |

Step by step (playing median / worst / menu): bevels and strings as GROUPS skipped whole when unchanged, one
list rewritten in place (10.6/21.5/8.1 -> 6.9/20.0/4.1); `kestrel_printf.c` (the labels' vsnprintf for the
common conversions, anything else to musl; `make printf-test`: 3,834 cases equal to the host C library),
`song_hash` a word at a time (~1 M -> ~0.27 M instructions every quarter second), keyed glyphs through a byte
map (-> 6.1/18.9/3.6); NOP entries, the resync after a dropped string, the group arena reusing a replaced
group's room, whole-command replays, the unscaled replay path, the present comparing only drawn columns (->
5.9/14.3/3.9). The same pixels: the six `HASHES` scenarios equal round 1's at every step; DPINTRO still loads
with its chorus (the draw cache lets go of its 293 KB, as in round 1). Cart 436 -> 445 KB.

From round 1's board reading (a repaint ~0.66x the estimate), a playing repaint averaging ~7.3 est should be
~4.8 Mc on the board: ~20 fps. A row change (~1 in 4 repaints at Starport2's speed) still redraws the pattern
view's text (~1,500 glyph copies); what is left there is pixels, not calls.

## Round 3 (perf/klystrack-ui-3, 4 Nov 2026)

Round 2 on the board: 5 fps for ~5 s after loading, then 60 idle; 15 fps while playing (and while moving the
pointer or opening a menu as it plays). What a frame redraws, from `make EXTRA=-DKESTREL_DEFER_STATS`
(`kestrel_defer.c` logs the last present every 30; off in the shipped cart), STARPRT2 playing:

| a present | entries | stored | groups reused / drawn | commands replayed | px idx / ARGB / fill | dirty tiles (of 600) | plane words stored |
|---|---|---|---|---|---|---|---|
| a tick between rows | ~3,200 | 0 | ~540 / 0 | ~90 | ~2,800 / 2,016 / 6,912 | 27 | 0 (the VU unchanged) to a few hundred |
| a row change | ~3,250 | ~700 | ~190 / ~400 | ~1,100-1,300 | ~37,000 / 2,016 / ~74,000 | ~310 | ~1,800-2,400 |

So neither the whole window nor the pointer is redrawn: between rows the present replays the VU meter
(2,016 ARGB px, BLEND) and ~90 small commands, and stores almost nothing; the pointer is a save-under
rectangle. What a repaint still costs is klystron itself: every view handler re-run and every label
formatted 30 times a second (pattern_view2, printf, the strings' group keys built and compared), ~0.9 M rv32
instructions over ~51 KB of code (the I$ term is ~60 % of the estimate). A row change redraws the pattern
view's text: ~400 strings drawn again (~2,500 glyph calls recorded) and ~1,200 commands replayed.

frame_cost est (Mc):

| | round 2 (main 5e44a51b) | round 3 |
|---|---|---|
| a repaint while playing, median | 5.92 | **4.86** |
| a repaint on a row change (worst) | 14.31 | **13.79** |
| menu open, pointer moving (a repaint a frame) | 3.87 | **3.21** |
| idle, pointer moving every frame | 0.74 | 0.74 |
| load: frame 1 (boot) | 191 | 181 |
| load: frames 2-60 / 61-140 (summed) | 362 / 215 | **124 / 58** |

The load: cyd mixed 2.2 s of exact silence before it could rest (~2.2 Mc a frame for 132 frames, under the 15
settling repaints); at boot nothing has sounded, so it now starts at rest (`kestrel_sdl.c`; cyd's own LFO/chorus
phases no longer advance through those 2.2 s, which only a keyjazz note on cyd could hear). The repaints: group
keys compared where they are, a group's commands skipped whole at the replay when none of its tiles is dirty,
the VU's ARGB copy without per-pixel tests. The same pixels: the six `HASHES` scenarios equal main's.

30 fps playing is not reached: at the board's speed about every other repaint is a row change, so the mean
repaint is ~(4.9 + 13.8) / 2 ~ 9 est. Getting there needs klystron-level work: skipping view handlers whose
inputs did not change (pattern view between rows, instrument and song panes), and the pattern view's scroll
drawn as a row copy plus one new row rather than ~400 strings again.

## Round 4 (feat/klystrack-r4, 6 Nov 2026)

Round 3 on the board (Matt, 4 Nov): 30 fps while a song plays, the top menus still slow, F11 ~300 %. That
percentage is the overlay's frame-budget line (ZIGGY + FRESCO busy against a 60 Hz frame, glass
`app_budget.zig`), not BARD: it was the repaints. Two levers, both klystron-level:

- **Views skipped when nothing they read changed** (`kestrel_view.c`, `kestrel_views.c`, `patches/view.c.sed`).
  `my_draw_view` runs each view inside an outer defer GROUP (groups now nest two deep, `kestrel_defer_group.c`:
  a view around its bevels and strings). Its key: the view (handler, param, area), what it reads that moves
  without an event (the timer's second, a slider's parameters, the sequence view's selected and play lines,
  the info line's step), a generation bumped by every event that reaches the views and every SDL timer that
  fired, mused's UI state (mode/focus/cursor block, flags, selection; the play and edit position only for
  the views that show it), and the draw state going in: clip, console, cursor and its target, and every
  texture's colour mod and blend (`kestrel_texstate.c`: one XOR word kept up to date by the renderer). The
  same key as last frame's group at that point, on a repaint with no event: its commands stay, the handler
  is not run, and the draw state it LEFT is put back (its outputs: clip, console, cursor, the textures it
  re-coloured). A view not listed in `kestrel_views.c` always draws (the analyzers, the instrument / FX /
  wavetable editors). `-DKESTREL_VIEW_CHECK` draws every view anyway and logs any that would have been
  skipped wrongly: none over `hashes.sh`'s scenarios (the pattern rows block is left out of it: drawn again
  it may take the other path, caches or upstream's pass, with other commands for the same pixels).
- **The pattern view split** (`kestrel_pattern.c`, `patches/pattern.c.sed`): the step counter and the
  channels' rows are blocks of their own; the VU meters (which move on every repaint while playing) are drawn
  after the rows block, each in its own channel's track. **The rows scroll in caches** (`kestrel_rows.c`): each
  channel keeps its text area as window pixels (rows in their normal colours over the background); on a row
  change the cache is memmoved by the rows the view moved and only the new row is drawn into it
  (`kestrel_defer_redirect`), the cache goes to the window as ONE command (a `raw8` texture: window indices
  copied as they are, its pixels kept through palette compactions), then the selected-row strip is drawn as
  upstream draws it there (background, bevel, the rows crossing it) into a strip cache. On an event the rows
  draw as upstream in one pass (a click reaches them as they draw and may move the view).
- `song_hash` (the .kt hand-over's edit check, ~0.4 Mc est every quarter second) runs only once an event has
  reached the views since the last check: an edit only comes that way.

frame_cost est (Mc a frame; the same tool and windows; before = main's round 3 rebuilt on today's main):

| | round 3 | round 4 |
|---|---|---|
| idle / idle, pointer moving | 0.72 / 0.74 | 0.72 / 0.75 |
| menu open, pointer moving (every frame) | 3.21 | **0.95** |
| playing: a repaint between rows (median) | 4.46 | **1.39** |
| playing: a row change (mean / worst, frames 161-280) | ~10.5 / 13.8 | **~8.2 / 9.5** |
| playing, mean a frame over 900 frames (palette compactions included) | 4.76 | **2.37** |
| playing + menu open (mean / worst) | 5.60 / 16.2 | **2.51 / 9.5** |
| playing + pointer moving (mean) | 3.99 | **2.17** |

A row change is still ~8 est: what is left there is mostly the replay and the present of the scrolled area
(~30,000 pixels a channel pair) and the I$ term of the ~60 KB of code a row change runs (the model charges
every instruction for it). At the board's ~0.66x of the estimate: menus and the repaints between rows fit
60 fps; a row change takes ~3 frames, so a song at ~8 rows a second should show ~45 fps.

The same pixels, `hashes.sh` (every frame hashed, 11 scenarios: idle, playing, menu, playing + menu, playing +
pointer, Ctrl+O dialog, keyjazz, edits while playing, clicks while playing, tab changes while playing, quit),
built from main's sources and this branch's **without the VU meters**: identical in every frame. With them,
`vu_proof.mjs` runs both and main's no-VU build in lockstep: every pixel that differs is a meter pixel (a
playing picture has more than 255 colours, so the palette maps the meters' gradient to the nearest entries
in the order colours arrive; at most 17 a channel), none outside the meters. The gate's UI pin is unchanged.

Memory: a cache is the track's inside, 148 x 104 = 15 KB for each of the classic view's two channels, plus a
148 x 9 strip, from the heap, and only from room to spare (64 KB over: a failed malloc would make the heap let
the draw list go); without it the rows draw as upstream. Cart 445 -> 452 KB.

## Round 5 (feat/klystrack-r5, 6 Nov 2026)

Round 4 on the board (glass ctl stats, 4 s windows, STARPRT2 via F5): idle 60.3 fps; playing, classic view 51.7
(33 missed, ZIGGY cart 0.91 Mc mean); instrument tab (F3) 47.6 (49 missed); back to the pattern tab (F2) 43.0
(67 missed); FRESCO flat. The misses were ZIGGY spikes: the row change and the views not on the skip list.

- **A hang on main**: F5, F3, F2, F3 (hashes.sh's play_tabs) never finished. With the instrument tab open again
  the picture holds ~250 colours, and every new blended colour compacted the palette (a scan of every tracked
  buffer, ~200 KB): one compaction a pixel. A compaction that frees fewer than 16 entries now stops them until
  the next present (`kestrel_palette.c`).
- **Occluded tiles** (`kestrel_defer_draw.c`): a tile wholly covered by a later opaque command (a clear, an
  opaque fill, a raw8 cache) leaves every command before it out of that tile. The candidates are marked at
  commit and kept in list order (a reused group carries last frame's), so the replay never walks the list for
  them. Under the scrolled caches the clear, the background and the track bevels are no longer drawn again.
- **The scrolled cache keeps its serial** (`kestrel_rows_diff.c`): its copy is last frame's command, and only
  the window tiles whose picture changes are named (`kestrel_window_dirty`). Each cache row keeps a hash of its
  pixels per 16-pixel tile column, taken when it is drawn; a scroll compares row i with row i + dr. Round 4
  moved the serial on every scroll: both whole tracks (~280 tiles) replayed.
- **The defer list's bookkeeping**: a group's tiles kept as its entries join it (not a walk over ~1,600 entries
  at its end; `-DKESTREL_GROUP_CHECK` compares), bands with the same dirty runs drawn as one rectangle.
- **Pixel loops**: a stretched bevel's texel drawn as a run (one memset, its length from one divide), keyed
  rows four texels a pass, the present comparing a drawn 16-pixel column 4 words at once.
- **The instrument tab skipped between events** (`kestrel_views.c`): instrument_view, instrument_view2,
  instrument_list read the song and the UI state only; program_view adds the program step of each channel
  playing the instrument (its cursor). The FX and wavetable tabs still draw every repaint (fx_view reads the
  mouse button held).

frame_cost est (Mc a frame; before = main with the palette fix, the same costs as main where main finishes;
frames 161-280; `prototypes/klystrack_r5_work/scen.mjs`-style windows, the gate's own windows in brackets):

| | round 4 | round 5 |
|---|---|---|
| idle | 0.72 | 0.72 |
| playing, classic view: mean / row change mean / between rows median | 2.10 / 8.59 / 1.47 | **1.92 / 7.34 / 1.44** |
| ...the gate's window: worst row change / mean | 9.31 / 2.03 | **7.82 / 1.85** |
| playing, instrument tab (F3): mean / repaint / worst | 2.02 / 3.04 / 3.24 | **1.04 / 1.32 / 1.47** |
| playing, back to the pattern tab (F2): mean / row change mean | 2.42 / 10.11 | **2.20 / 8.78** |
| menu open, pointer moving (worst) / playing + menu (mean) | 0.95 / 2.51 | 0.98 / **2.30** |

At round 4's board ratio (~0.66), the instrument tab's repaints (~0.9 Mc) fit 60 fps; a row change (~4.8 Mc on
the board, was ~5.7) still spills over two frames. What is left in it (1.3 M rv32 instructions, 65 % of the
estimate the I$ term over ~63 KB of code): replaying the dirty tiles no cache covers (the track edges, the step
counter, the bottom scroll bar whose band the last row touches, the sequence view under its moving play line:
~13,600 keyed and ~14,000 stretched texels, ~660 draws), the present comparing them (D$ misses), the replay's
walk (~1,350 entries, a D$ miss each) and klystron's views (~0.35 M). Reaching ~2.5 est needs fewer layers
there (an occluder that is not tile-aligned, a snapshot of a view's static layers) or smaller tiles.

The same pixels: `hashes.sh` (now 12 scenarios with play_inst: F3 while playing, clicks on a parameter, the
instrument list and the program; each run under a timeout) built without the VU meters, main + the palette fix
against round 5: identical in every frame; `vu_proof.mjs` with the meters (play 420 frames, play_tabs 300):
0 frames differ. `-DKESTREL_VIEW_CHECK -DKESTREL_GROUP_CHECK` over all 12 scenarios: no wrong skip, no box that
differs. Cart 452 -> 458 KB.

## What's left

- In the browser, Ctrl+O / Ctrl+S are also browser shortcuts; whether the loader swallows them for a cart that
  `ownsKeyboard` is the host's business (headless they reach klystrack).
- Read-only floppy: saving songs/instruments/wavs fails (klystrack reports it); the config file is never written.
- The Themes and Keymaps menus list every file on the flat floppy (picking a song as a theme fails harmlessly).
- Pixel scale / fullscreen / window-size menu items are no-ops or wrong (the screen is fixed at 320x240 at scale 1).
- 22.05 kHz mixing and one reverb at most (memory, above). No MIDI.
- Songs with more than 256 patterns or sequence entries are refused (examples that save all 4096 patterns:
  AmsterdamBoppe, StarChips, dr.happy, smp_dingleberries_fix). Lazily allocated pattern steps would lift the cap.
- KESTREL board (2 Nov): 7.3 fps. cyd mixes at 22.05 kHz without oversampling now (`patches/cyd.c.sed`,
  `mused.c.sed`: upstream's 4x, which `cyd_init` set after the config was applied), ~13,000 cycles a sample
  (`apps/frame_cost.mjs`; ~16,000 at 4x): more than real time leaves. The feed is capped at 2 frames of audio
  a frame so the UI keeps its rate; the song plays slow on the board until cyd fits the budget.
- perf/ports-synth (frame_cost, STARPORT2 playing): est 47.5 -> 34.8 Mc a frame (cart 13.96 -> 9.81), idle
  33.6 -> 24.9 (cart 8.87 -> 6.68). UI: the renderer's indexed fast path and word presents (RenderCopy ~6.3 ->
  ~2.4 Mc, present 1.27 -> 1.0); the same pixels (the gate's UI pin did not move). Synth: `-DLOWRESWAVETABLE`
  (klystron's own option: 32-bit wavetable accumulators instead of u64 with i64 divides), the reverb taps and
  the skipped buses/channels above: ~15,400 -> ~12,500 cycles a sample, the stream bytes unchanged. Still ~2.7x
  real time at 22.05 kHz: per sample, 8 channels of cyd (oscillators, wavetable, FM, ADSR, filter, stepping: ~9,900),
  2 reverb buses of 16 taps reading 345 KiB delay lines (~2,200, D$ misses) and the chorus (~300). What would fit: fewer
  channels or FX taps a song, cyd at a lower rate, or cyd on BARD. The 33 ms cap stays.
- Registered (catalog, disk, `apps/ports_headless.mjs` in build.sh) on 2 Nov 2026.
- perf/klystrack-board (2 Nov; Matt's board: 5-6 fps idle, OSD cart_c 19.9 Mc doing nothing, ~11 s to the first
  picture). `apps/frame_cost.mjs`, est Mc a frame (cart part in brackets), same tool and windows before/after:

  | | before | after |
  |---|---|---|
  | idle, steady (frames 201-260) | 24.9 (cart 6.7): a full repaint every other frame, 46.7 / 3.2 | **0.72** (cart 0.02, the rest FRESCO's one plane) |
  | idle, first 2.2 s after a sound | same | 3.1 (cyd mixing silence until the reverb line has drained) |
  | playing STARPORT2 (F5) | 34.8 (cart 9.9) | 34.2 (cart 9.7) |
  | boot() (`--warmup 0 --frames 1`) | 1002 (cart 708) | 204 (cart 54) |

  Where idle went: klystrack repaints its whole UI at 30 Hz whatever happens (`gfx_domain_is_next_frame`), ~45 Mc
  est (I$ 70 % of it: the repaint runs ~32 KB of code), and cyd mixed 8 silent channels every sample (~2.4 Mc).
  Boot: 630 Mc of soft-float `sin()` building the chorus LUT, malloc's first-fit walk (23 Mc), the theme's
  per-pixel hashing. Playing is unchanged in kind: one repaint (~7 Mc cart: ~2,400 glyph blits, the present's
  ARGB -> 8-bit convert, printf) plus cyd at ~12,500 cycles a sample (2.7x real time at 22.05 kHz), so the song
  still plays slow on the board and the UI is ~3-5 fps while it plays. Next: an 8-bit renderer target (textures are
  already indexed, the UI ~32 colours: draw straight into the plane, no present), and cyd itself (BARD, or
  fewer channels / taps). The gate (`apps/ports_headless.mjs klystrack`) now also moves the pointer over the idle
  UI (`--break pointer`) and presses F5 only after cyd has gone quiet. A keyjazz note ('z') after cyd went quiet sounds as
  before (gate set at trigger, peak |s8| 9 on both builds). Disk: boot() reads 1,397 blocks (715 KB, ~3x the 245 KB
  floppy; theme bundle and song re-read) through the one-block cache: ~2 Mc of copying in the cart, the firmware's
  per-block cost unmeasured (`DISK_BLOCK` = 0 in the cost model); not what made the boot slow.
