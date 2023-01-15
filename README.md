# ZigMachine

A [Fantasy Console](https://en.wikipedia.org/wiki/Fantasy_video_game_console) written in [Zig](https://ziglang.org/) and running in the browser as a [Web Assembly](https://webassembly.org/) binary. The ZigMachine is dedicated to provide a fun sandbox to learn how to code [oldskool effects](https://www.pouet.net) as no advanced features are provided, only the basics of the 80s computers and video game consoles.

This project is inspired by [WAB](https://wab.com) and [CODEF](https://codef.santo.fr) by my friend NoNameNo who.. already more than 10 years ago... provided a way to code oldskool effects in the browser without Flash but only HTML5 and javascript. Time to go one step further. 0% Flash, 0% HTML, 0% Javascript, only Zig!

Screenshots below!
Live website with the latest build: [ZigMachine](https://shazz.github.io/ZigMachine/)

## Specs

The specs of the ZigMachine will definitively evolve over time but for now they try to match what I would have loved to get in the 80-90s:

- 2 MB of RAM
- 1 physical RGBA framebuffer of 400x280 pixels without borders, 320x200 pixels with borders.
- 4 logical linear indexed colors framebuffers (each pixel is an entry of the 256 colors RGBA palette) of 320x200 pixels
- 1 palette for each logical framebuffer
- CPU frequency is what your Web Assembly browser framework can do. So, pretty (too...) fast. I'd love to be able to provide a restricted and stable execution speed one day if I find a way to do it.
- Limited ZigOS for basic setup
- Some kind of non-interrupted VBL and HBL callbacks

In addition to the fantasy console and the ZigOS, a library for classic oldsk00l demo effects is provided featuring:
- horizontal scrolltext with offset curves
- 2D starfield
- 3D starfield
- 3D transformations
- pixel and line drawing
- Sprites
- Fading

And so examples!

Next in my TODO list:

- 1 digital sound channel (44100Hz, 32 bits)
- YM2149 emulation
- Blitter emulation for line drawing and polyfilling.
- Mapped memory in addition to OS functions
- Emulated hardware scrolling

For the moment, only Zig is supported to code stuff on the ZigMachine (so the name...) but maybe one days so custom 68K like assembly code or probably raw web assembly. Who knows :) 
Want to add things? Please leave a message in the [Discussions](https://github.com/shazz/ZigMachine/discussions)

## Build

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

Go to your favorite browser and type to the URL `http://localhost:3333` or `http://localhost:3333/debug.html` for a debug view.

## Screenshots

![image](https://user-images.githubusercontent.com/604708/211934422-c38a40db-cdcb-48a3-9c7b-016d1e4fbe04.png)
![image](https://user-images.githubusercontent.com/604708/211934911-e95d1c98-2d77-4c42-99a6-9e7a7b51ed3e.png)
