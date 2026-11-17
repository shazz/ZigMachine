# zigdemo: the demo engine

The generic parts of a demo engine: a master clock, a timeline of parts, fixed-point
curves, a part interface, the per-frame flow, and debug scrubbing. A cart describes its
demo as data and a few part structs; zigdemo does the sequencing.

## Where it comes from

Ported from **The Black Lotus's** demo system, in their PSP demo *Suicide Barbie*
(MIT licence, © The Black Lotus). The ideas come from `Code/Modules/player/` (`Timeline.h`,
`TimeControl`, `DemoPlayer`, `Animators`) and the demo script `Tests/MutaliskViewer/TestDemo.cpp`.
The code is a rewrite in idiomatic Zig: no vtables, no per-frame allocation, no float per frame.
The study notes are `prototypes/suicide_barbie_re/ANALYSIS.md` §7 (a local, gitignored study).

## Module map

| file | lines | what |
|---|---|---|
| `clock.zig` | 135 | Master time (u32 ms) and the 60 Hz frame index. Follows a source the cart reads: samples fed minus ring fill, song ms, or VBL. Pause, jump, A-B loop, and a seq counter that `Reader` reads. |
| `timeline.zig` | 138 | TBL's Timeline as data: tracks of `draw` and `once` items, `gather` (forward fires, backward does not), `jump` (replays a load track's once items up to now). |
| `curve.zig` | 104 | Integer tracks: `linear` and `step` (sparse keys), `baked` (fixed-rate i16 samples). Q16 interpolation. `Trs` is a compile-error stub. |
| `part.zig` | 71 | `Dispatch(Ctx, Parts)`: the cart's `union(enum)` of parts, dispatched by `inline else`. |
| `demo.zig` | 108 | `Demo(Parts, Ctx, tracks)`: clock, timeline and active parts. `update`, `render`, `deinit`. |
| `debug.zig` | 71 | Scrub keys (pause, ±1 s, ±10 s, next/prev item, A-B marks) and `formatTime` (mm:ss.cc). |
| `assets.zig` | 68 | **MOCK**: two slots and a prefetch queue; loads at once from a table. |
| `audio.zig` | 36 | **MOCK**: a 60 Hz sample counter, exact at rate/60. No sound. |
| `r3d.zig` | 32 | **MOCK**: 3D types only (`Vec3`, `Mesh`, `Material`, `Actor`, `Camera`). No maths. |
| `nfo.zig` | 190 | NFO / ASCII-art viewer core: CP437 text painted once into a tall 640-wide buffer, a 1 px scroll (`update`, `scrollTo`, `scrollBy`), a fixed prompt bar, `key()` for the keys a loader offers. Hardware-free; module `nfo` in build.zig. |
| `nfo_render.zig` | 110 | Text split into 80-column lines, one pixel row at a time with the viewer's drop shadow; the prompt bar. |
| `nfo_glyph.zig` | 110 | The 8x9 cell: blocks, shades (dither), grid lines, the palette. |
| `nfo_font.zig` | 140 | Our own 8x8 ASCII font (original pixel work, as pictures in the source; no Topaz ROM data). |
| `nfo_cp437.zig` | 80 | UTF-8 to CP437, at comptime for an `@embedFile`d text; an unmappable code point is an error. |
| `nfo_plane.zig` | 20 | Binds an `Nfo` to the desk plane (`attach`, `frame`); `fb` is `anytype`, so no zigos import. |
| `nfo_menu.zig` | 90 | A menu PANEL over the page: the cart's CP437 art (a block frame round its choices, same cell, font, colours and shadow), its choice keys; Space opens / closes, Esc closes, a key chooses while open. Keys only queue: `Nfo.update()` paints the panel into the window's middle rows or restores them, and holds the scroll while it is open. `Nfo.setMenu(bytes, keys)`, then `nfo.menu.?.key(cp)`. |
| `zigdemo.zig` | 14 | Umbrella: re-exports the modules and `Demo`. |

Tests are `*_test.zig` siblings, run natively by `build.sh` (the NATIVE_TESTS list).

## What is real and what is mocked

Real and tested: the clock (sources, pause, seek, loop, u32 wrap), the timeline (cursors,
once firing, jump replay, same-start items, empty tracks), the curves (edges, keys, between),
the part dispatch, the demo flow, the scrub keys and the time text.

Mocked, each marked in its file:
- **assets**: the disk streaming (64 KB a frame) and the zx0 step-depack. The mock keeps the
  queue and the slots and loads at once.
- **audio**: the ADPCM/PCM stream and the re-seek of the ring. The mock keeps a sample counter.
- **r3d**: types only. The renderer is the next step (ANALYSIS §7 (3)).
- **Trs curves**: a compile error if called, so no cart ships an identity pose by accident.
- The overlay drawing (`debug.formatTime` gives the text; the cart draws it).

Not built yet: the `timeline.zon` generator (`gen_timeline`) that would compile a
timeline from text, and a cart that uses zigdemo (the optional example).

## How a cart uses it

Items are data. A cart declares its parts as a union; the tag order is the item's part id.

```zig
const zigdemo = @import("zigdemo");

const Ctx = struct { pal: *Palette, assets: zigdemo.assets.Assets };

const Fade = struct {
    pub fn init(self: *Fade, ctx: *Ctx, arg: u16) void { _ = self; _ = ctx; _ = arg; }
    pub fn update(self: *Fade, ctx: *Ctx, t_ms: u32) void { _ = self; _ = ctx; _ = t_ms; }
    pub fn render(self: *Fade, ctx: *Ctx, t_ms: u32) void { _ = self; _ = ctx; _ = t_ms; }
    pub fn once(ctx: *Ctx, arg: u16) void {
        ctx.assets.request(arg) catch |e| @panic(@errorName(e));
    }
};
const Bar = struct { pub fn update(self: *Bar, ctx: *Ctx, t_ms: u32) void { _ = self; _ = ctx; _ = t_ms; } pub fn render(self: *Bar, ctx: *Ctx, t_ms: u32) void { _ = self; _ = ctx; _ = t_ms; } };
const Parts = union(enum) { fade: Fade, bar: Bar };

const draw = [_]zigdemo.timeline.Item{
    .{ .start_ms = 0, .part = 0, .kind = .draw, .arg = 0 },
    .{ .start_ms = 4000, .part = 1, .kind = .draw },
};
const load = [_]zigdemo.timeline.Item{
    .{ .start_ms = 0, .part = 0, .kind = .once, .arg = 3 },
};
const tracks = [_]zigdemo.timeline.Track{
    .{ .items = &draw },
    .{ .items = &load, .replay_once = true },
};

const Demo = zigdemo.Demo(Parts, Ctx, &tracks);

// Per frame: the cart re-seeks its sound on a seek FIRST, then updates the demo.
var demo = Demo.init();
if (audio_reader.changed(&demo.clock)) music.seekMs(demo.clock.t);
demo.update(music.source(), &ctx);
demo.render(&ctx);
```

The loop wrap happens inside `update`, so the sound re-seeks one frame after the wrap: the
clock holds `a` on that frame and then follows the re-seeked source. That lag is correct; do
not move the wrap out of `update`.

`update` moves the clock from the source, fires the once items crossed (or replays the load
track after a seek or a loop wrap), starts and ends the draw parts whose item changed, and
updates the active ones at their local time (`now - item.start_ms`). `render` draws the active
parts in track order. A part that is a transition renders two parts itself.

To use zigdemo from a cart, add the module to the cart's imports in `build.zig` the way
`tvnoise` is (`libs/zig/zigdemo/zigdemo.zig`, no imports of its own). It is not in `build.zig`
yet, because no cart consumes it.

## The NFO viewer

`nfo.zig` renders an NFO the way an Amiga ASCII viewer shows it: blue background, white text with a dark
drop shadow one pixel down and right, blocks with a faint grid, shades as dithers. Cell 8x9, 80 columns =
640 px, so it needs the desk mode (640x480, square pixels; medium's pixels are twice as tall as wide).

```zig
const nfo = @import("nfo");                       // module in build.zig
const text = nfo.cp437.comptimeFromUtf8(@embedFile("my.nfo.txt"));
var v = try nfo.Nfo.init(text, .{ .frames_per_px = 2, .prompt = "press O or K", .keys = "OK" });
try nfo.plane.attach(&v, &zigos.lfbs[0]);         // once: tall buffer, palette, paint, pan to 0
nfo.plane.frame(&v, &zigos.lfbs[0]);              // every frame: v.update() then setScroll(0, y)
if (v.key(cp)) |k| { /* the cart decides what 'O' / 'K' mean */ }
```

`Nfo.init` errors on a text over 160 lines, a prompt over 80 columns, `frames_per_px == 0`; lines over 80
columns are cut. The text is painted once; a scroll step only rewrites the 18 bar rows and the one text row
the bar uncovers (the desk has one plane, so the bar lives in the buffer). Characters with no glyph yet
(accents, Greek, line drawing) show as a hollow box. Example cart: 138 `nfo_viewer`
(`apps/zig/scenes/nfo_viewer.zig`), harness `apps/nfo_viewer_check.mjs`.
