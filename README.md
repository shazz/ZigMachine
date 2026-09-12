# ZigMachine

A [Fantasy Console](https://en.wikipedia.org/wiki/Fantasy_video_game_console) (or Fantasy Computer, not sure) written in [Zig](https://ziglang.org/) and running in the browser as a [Web Assembly](https://webassembly.org/) binary. The ZigMachine is dedicated to provide a fun sandbox to learn how to code [oldskool effects](https://www.pouet.net) as no advanced features are provided, only the basics of the 80s computers and video game consoles.

This project is inspired by [WAB](https://wab.com) and [CODEF](https://codef.santo.fr) by my friend [NoNameNo](https://github.com/N0NameN0) who... already more than 10 years ago... provided a way to code oldskool effects in the browser without Flash but only HTML5 and javascript. Time to go one step further. 0% Flash, 0% HTML, 0% Javascript, only Zig!

Screenshots and live version below!

## Live version

Live website with the latest build: [ZigMachine](https://shazz.github.io/ZigMachine/) (Click on the + and - buttons to change channels!)

## The machine is sealed

The big idea, and the thing that makes this more than a demo loop: **the hardware is a separate binary from the software running on it.**

The browser loads four wasm modules that share ONE `WebAssembly.Memory`:

| module | thread | what it is |
|---|---|---|
| `machine-video.wasm` | main | the sealed video hardware — shifter, borders, blitter |
| `machine-audio.wasm` | worklet | the sealed sound hardware — YM2149 + 4 sample channels |
| `demo.wasm` | main | **your** code: the cart currently in the slot |
| `demo-audio.wasm` | worklet | **your** players, driving the sound chips |

They talk through a memory-mapped register ABI (`machine/sdk/`), exactly like poking hardware registers on a real machine. The app cannot reach inside the hardware, and the hardware cannot see the app — so the machine can be handed to someone else and still behave.

A fifth module, `rom.wasm`, is the system software (GEM — a desktop, windows, dialogs and a file manager), which carts call through a flat handle-based ABI rather than linking it.

The host JavaScript is deliberately dumb: it is glass and a speaker. It blits the framebuffer, forwards input, and plays the file a scene asks for. Everything else happens in wasm.

## Specs

The specs will keep evolving, but they try to match what I would have loved to get in the 80-90s:

#### Memory / CPU

- 7 MB of shared linear memory (112 pages of 64 KB), of which a cart gets a **2 MB window** for its code, data and stack — and the build fails if it overruns.
- CPU frequency is whatever your browser's WebAssembly can do. So, pretty (too...) fast.
- Assets can be **ZX0-packed** and depacked into free cart RAM at run time (~38% of raw across the whole shelf).

#### Graphics

- 1 physical RGBA framebuffer, 400x280 with borders, 320x200 visible.
- 4 logical indexed framebuffers (each pixel an entry in a 256-colour RGBA palette), composited as stacked layers — palette entry alpha 0 is transparent.
- 1 palette of 256 colours (RGBA, 8 bits per component) per logical framebuffer.
- Per-scanline (HBL) and per-frame (VBL) callbacks, per-plane and global — this is how you do copper bars.
- **Overscan the honest way**: there is no "fullscreen" flag. You open a border by flickering the resolution register from an HBL handler at exactly the right column, as on real hardware. Miss the column and you get garbage on that line.
- Blitter, hardware scrolling, and a `copper` helper for per-line palette tables.

#### Sound

- **YM2149 PSG** + 4 Paula-style sample channels, both sealed hardware.
- Players (the open half): ProTracker MOD, YM register dumps, raw PCM streaming off a disk, and **SNDH — which runs the tune's own 68000 replay code on an emulated Motorola 68000** (Musashi), trapping its PSG writes to the sealed chip. The chip music is genuinely being played by the original driver.
- A scene just asks for a tune by name; the machine reclaims the sound chip when a program ends.

#### OS

- **ZigOS**, the open library layer: planes, palettes, HBL handlers, blitting, text.
- **GEM** in `rom.wasm`: a TOS-1.00-style desktop with windows, icons, dialogs, drag and drop, rename, and `DESKTOP.INF`.
- Programs live on **floppies** (`.zmd`) with a FAT and a bootable sector; GEM can launch one off the disk, and an app can quit back to the desktop.

#### Demo framework

Reusable oldskool effects: scrolltexts (with X/Y offset tables), 2D/3D starfields, 3D transforms, triangle/line/pixel drawing, sprites, bobs, fades, tile engines, parallax, and a clipped signed-coordinate blitter.

## Any language, not just Zig

The seal is a **wasm ABI, not a Zig API**, so a cart can be written in anything that compiles to wasm. `apps/c/` and `apps/rust/` hold working carts — including a full cracktro port in C that opens the borders with the same resolution-flicker trick, driven entirely by register pokes and an exported HBL callback from C.

```
apps/zig/scenes/    the Zig scenes (one cart each)
apps/c/scenes/      C carts        apps/rust/   Rust carts
machine/            the sealed hardware + its SDK headers
rom/                system software (GEM)
libs/{zig,c,rust}/  reusable libraries (ZigOS lives in libs/zig)
docs/               the web root, the built wasm, and the API docs
```

## The channels

34 screens ship as cartridges, most of them ports of Atari ST cracktros and demo screens from [WAB](https://wab.com)'s CODEF remakes. The `+` / `−` buttons on the monitor step through them like TV channels, with an analogue-noise transition; the boot menu lists them all.

**Credit belongs to the originals.** Each scene's source header names the demo, its coders, graphicians and musicians, and the author of the CODEF remake it was read from. CODEF itself is MIT-licensed. The music is from the [SNDH archive](https://sndh.atari.org). If you are one of the original authors and would rather your work were not here, please open an issue.

## Docs

- `docs/HW_API.md` — the sealed hardware ABI
- `docs/ZIGOS_API.md` — the open library
- `docs/HARDWARE_SPEC.md` — design and status
- `docs/FLOPPY_DISK.md` — the disk format
- `decisions.md` — architecture decision records

## Build

### Prerequisites

- [Zig 0.16.0](https://ziglang.org/download/)
- [Python 3](https://www.python.org/downloads/) for the asset tools and the dev server
- Node (optional) for the headless test harnesses

The only target is `wasm32-freestanding-musl`.

```shell
./build.sh
```

That builds every module and cart, then runs the gate: RAM-window checks, the native tests, a repack of every floppy, and headless harnesses that drive the real machine end to end. Use it instead of a bare `zig build` — the failures it catches are the silent ones, like a cart overrunning its window and corrupting the video region instead of trapping.

## Run

```shell
./serve.sh          # serves docs/ with no-store caching
```

Then open `http://localhost:3333`. Hard-reload (Ctrl+Shift+R) after a rebuild.

To boot straight into one cart: `http://localhost:3333/?demo=demo-dbug.wasm`

## Screenshots

![image](https://user-images.githubusercontent.com/604708/215280926-3705f596-1b46-426a-ae2e-cede1a5f4e1d.png)
![image](https://user-images.githubusercontent.com/604708/215281094-e26adf7d-2582-4f45-8826-25e11ff84fcd.png)
![image](https://user-images.githubusercontent.com/604708/215281318-dea95451-233b-4fe5-b7fb-7a4da2e33c7b.png)

Want to add things? Please leave a message in the [Discussions](https://github.com/shazz/ZigMachine/discussions).
