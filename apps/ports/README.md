# C program ports

Desktop programs in C/C++ on SDL2, rebuilt as ZigMachine carts. Each runs from its own floppy
(`docs/demo-<tag>.zmd`) and is listed in the menu like a screen.

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
harness for all four. Why it is laid out this way: decisions.md, "C program ports live in apps/ports".
