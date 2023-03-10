# ZigMachine

A [Fantasy Console](https://en.wikipedia.org/wiki/Fantasy_video_game_console) (or Fantasy Computer, not sure) written in [Zig](https://ziglang.org/) and running in the browser as a [Web Assembly](https://webassembly.org/) binary. The ZigMachine is dedicated to provide a fun sandbox to learn how to code [oldskool effects](https://www.pouet.net) as no advanced features are provided, only the basics of the 80s computers and video game consoles.

This project is inspired by [WAB](https://wab.com) and [CODEF](https://codef.santo.fr) by my friend [NoNameNo](https://github.com/N0NameN0) who... already more than 10 years ago... provided a way to code oldskool effects in the browser without Flash but only HTML5 and javascript. Time to go one step further. 0% Flash, 0% HTML, 0% Javascript, only Zig!

Screenshots and live version below! 

## Live version

Live website with the latest build: [ZigMachine](https://shazz.github.io/ZigMachine/) (Click on the + and - buttons to change channels!)

## Specs

The specs of the ZigMachine will definitively evolve over time but for now they try to match what I would have loved to get in the 80-90s:

#### Memory / CPU

- 2 MB of RAM available (32 pages of 64KB).
- CPU frequency is what your Web Assembly browser framework can do. So, pretty (too...) fast. I'd love to be able to provide a restricted and stable execution speed one day if I find a way to do it. Currently my not-that-optimized flat shaded triangle routine can display around 1000 triangles/frame.

#### Graphics

- 1 physical RGBA framebuffer of 400x280 pixels without borders, 320x200 pixels with borders.
- 4 logical linear indexed colors framebuffers (each pixel is an entry of the 256 colors RGBA palette) of 320x200 pixels
- 1 palette of 256 colors (RGBA, 8 bits per component) for each logical framebuffer.
- Blocking VBL and HBL callbacks on logical framebuffers and on the physical framebuffer.
- Overscan possible but a little tricky to set up else no fun!

#### Sound

- Nothing yet! Soon! (Hopefully)

#### OS

- Limited ZigOS for basic setup and framebuffer managemenent.
- 8x8 sytem font with print capability

#### Demo framework

In addition to the fantasy console and the ZigOS, a library for classic oldsk00l demo effects is provided featuring:

- Horizontal scrolltext with offset tables in X and Y
- 2D starfield
- 3D starfield
- 3D transformations
- Triangle, line and pixel drawing
- Sprites
- Bobs
- Screen fading
- Background image
- Static text display

I started to port some of my favorites Atari and Amiga cracktros (from WAB) to show how to use the ZigMachine. Check the source code and the channels in the live demo.

#### Next in my TODO list:

- Stero digital sound channel (44100Hz, 32 bits).
- Soundchip (YM2149 probably) emulation.
- Blitter emulation for line drawing and polyfilling.
- Mapped memory in addition to OS functions.
- Emulated hardware scrolling.
- Z-Buffer, face culling, Gouraud shading.
- 3D Objects loader.

For the moment, only Zig is supported to code stuff on the ZigMachine (so the name...) but maybe one day, some custom 68K like assembly code or probably inline Web Assembly. Who knows :) Want to add things? Please leave a message in the [Discussions](https://github.com/shazz/ZigMachine/discussions)

### Project status

The project status is available here: https://github.com/users/shazz/projects/2/

## Build

### Prerequisites

- [Zig 0.10.0+ ](https://github.com/ziglang/zig/wiki/Install-Zig-from-a-Package-Manager)
- [Python 3+](https://www.python.org/downloads/), pretty nice to preprocess images and host the wasm with one line
- Optional VScode with Zig extensions

The default (and only) target for this build is `wasm32-freestanding-musl`.

To build the wasm module, run:

For Web Assembly

```shell
% zig build -Drelease=true -Dwasm
```

Note: `build.zig` specifies various wasm-ld parameters. For example, it sets the initial memory size and maximum size to be xxx pages, where each page consists of 64kB. Use the `--verbose` flag to see the complete list of flags the build uses.

## Run

Start up the server in the html directory:

```shell
cd docs
python3 -m http.server 3333
```

Go to your favorite browser and type to the URL `http://localhost:3333` or `http://localhost:3333/debug.html` for a debug view of each logical framebuffer.

## Screenshots

![image](https://user-images.githubusercontent.com/604708/215280926-3705f596-1b46-426a-ae2e-cede1a5f4e1d.png)
![image](https://user-images.githubusercontent.com/604708/215281094-e26adf7d-2582-4f45-8826-25e11ff84fcd.png)
![image](https://user-images.githubusercontent.com/604708/215281318-dea95451-233b-4fe5-b7fb-7a4da2e33c7b.png)




