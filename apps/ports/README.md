# C program ports

Desktop programs in C/C++ on SDL2, rebuilt as ZigMachine carts. Each is a GEM program on its own DATA floppy
(`docs/demo-<tag>.zmd`), as ST Replay and SysInfo are, and is listed in the menu like a screen: the machine
boots GEM over the disk, the FLOPPY window shows the program (`BOOT.WSM`) beside its files (modules, pictures,
songs; 8.3 names, GEM lists 12 at most), a double-click runs it (request 3), and the program's own quit brings
the desktop back (request 4) with the disk still in the drive. The program reads its files off that disk.
Each disk carries the "SDL" boot sector (`docs/boot-sdl.wasm`, `apps/zig/boot/sdl.zig`), which runs before GEM
(as SysInfo's "No virus" sector; `tools/mkdisks.sh` `portdisk`).

Quitting is in the shared layer, `kestrel_sdl2/src/kestrel_quit.c`: `kestrel_quit()` makes the cart's
`pollCartRequest` export answer 4. `SDL_Quit()` calls it, `exit()` calls it before it traps, and each port
calls it where its main loop ends:

| port | quit | how it reaches `kestrel_quit()` |
|---|---|---|
| pt2 | Esc on the main screen (or Alt+Q, the QUIT button), Esc again within 3 s to confirm | `editor.programRunning` false at the end of `pt2_frame` (`split_main.py`); the confirm replaces `askBox("REALLY QUIT ?")`, whose modal loop never returns on a cart (`patches/pt2_{keyboard,mouse}.c.sed`) |
| GrafX2 | Q (the Quit button), then Discard / Save on its "Quit ?" box if the picture changed | `grafx2_main` returns (`kestrel_main.c`; its `SDL_Quit()` too) |
| klystrack | Esc (Quit), Alt+F4, or the menu's Exit | `klystrack_main` returns (`kestrel_main.c`) |
| ChipNomad | SETTINGS (SELECT + Down from the song screen), "Quit ChipNomad", A | `mainLoopTriggerQuit` (`kestrel_main.cpp`) |

| dir | cart | upstream | pinned commit | licence |
|---|---|---|---|---|
| `pt2/` | `demo-pt2` | [pt2-clone](https://github.com/8bitbubsy/pt2-clone) (Olav "8bitbubsy" Sørensen) | `d42d5f1` | BSD-3-Clause |
| `grafx2/` | `demo-grafx2` | [GrafX2](https://gitlab.com/GrafX2/grafX2) (the GrafX2 team) | `678a0f5` | **GPL-2.0** |
| `klystrack/` | `demo-klystrack` | [klystrack](https://github.com/kometbomb/klystrack) + klystron (Tero "kometbomb" Lindeman) | `fe6e746` + `1074324` | MIT |
| `chipnomad/` | `demo-chipnomad` | [ChipNomad](https://github.com/Megus/chipnomad-tracker) (Megus) | `e4b10d5` | MIT |
| `kestrel_sdl2/` | (shared) | ours: SDL2-shaped headers, heap, WASI over the floppy, input, opt-in renderer/RWops/timers | | MIT (the repo's) |

Upstream is **not** vendored here: each port keeps only our glue (`kestrel_*`), the `patches/*.sed` applied to a
mirror of upstream in `build/gen/`, its Makefile, a headless runner (`run.mjs`) and its own disk data.
`fetch.sh` clones every upstream at its pinned SHA, plus binaryen 132 (Asyncify, for GrafX2 and klystrack),
into `upstream/` (gitignored), and checks each one.

    apps/ports/fetch.sh                    # once
    make -C apps/ports/<port> link         # build/demo-<tag>.wasm
    make -C apps/ports/<port> install      # copy it to docs/ and repack the disk (tools/mkdisks.sh)

The carts in `docs/` are committed prebuilt, as `apps/c` and `apps/rust` carts are: `./build.sh` does not
rebuild them (it needs the upstream checkouts), and a rebuild at the pinned commits is byte-identical.
`tools/mkdisks.sh` packs each disk from the committed cart and files. `apps/ports_headless.mjs` is the gate's
harness for all four: it boots GEM over the disk, launches `BOOT.WSM` from the FLOPPY window
(`apps/ports_gem.mjs`), uses the program, then quits it and checks the desktop comes back. Why it is laid out this way: decisions.md, "C program ports live in apps/ports".
