# GEM desk mode: one 640x480 plane, shown 1:1 (study)

Status: **study, Matt to decide** (branch `study/gem-640x480`, 7 Nov 2026). No RTL, no bitstream, no
sim was run for it. Every LUT figure below is an estimate from existing reports, not a synthesis.

Matt, 7 Nov: "the minimal GEM only 640x480, no need to support any raster, compositing, fullscreen...
the minimal to show tools like Devpac or any GEM application" (and TUIs). It is not a demo mode.

The software side (what ZigGEM must abstract) is in `docs/DEVPAC_GAP.md` §3b on `study/devpac-gap`.
This study is the hardware side, and it closes the ROADMAP row "FRESCO 640x400 mode (one 8-bit plane)"
of 1 Nov: 640x480 replaces 640x400 (the same mechanism, 80 more lines).

## Summary

- **The mode.** `RESOLUTION = RES_DESK` (3). Plane 0 only: 640x480 bytes from the VRAM pool, stride
  640, palette 0, shown 1:1 (no pixel or line doubling) in the middle of the 800x600 output (80 px
  sides, 60-line bars, black). No other plane, no HBL handler (global or plane), no copper, no linepal,
  no BEAM, no overscan flicker, no HSCROLL, no true colour, no alpha.
- **The compositor is bypassed, not changed.** The scanout fetch reads plane 0's lines straight from
  memory (80 beats a line instead of the picture's 400) and the palette lookup moves into the pixel
  clock, on a mirror of palette 0. `zm_video_comp` (FRESCO's compositor, the block every break test
  guards) keeps its netlist. The sequencer issues no pass in desk mode. It waits for the swap
  (`vseq_wait_swap`, as `vseq_mix_only` does), then issues PRESENT, so the frame stays paced at the VBL.
- **Cost (estimate).** About 150-230 LUT and 2 RAMB18 for the mode, plus 60-100 LUT for a hardware
  pointer (needed: below). The board is at 90.3 % LUT on the 3 Nov estimate (15,893 / 17,600) before
  CHISEL v2's +952, so ~95.7 % with it: **this needs a payer** (Matt's decision, §9).
- **Speed.** DDR traffic for the picture: 18.4 MB/s (today 53.8 MB/s of scanout plus ~170 MB/s of
  row I/O per composited plane, TRUECOLOR_PLANE.md's figure). The cart CPU gets back the ~0.7 Mc a frame FRESCO costs a one-plane
  desktop today. The scanout's margin grows: 80 beats in one line time (26.4 us) instead of 400 in two.
- **The oracle survives.** The desk picture is a pure function of plane 0 and palette 0. The sealed
  machine computes it (`hwRenderDesk`), and the page, `scene_hash.mjs`, the native host and hp_sim hash
  that output. A testbench proves the RTL's wire equals it.
- **Effort.** About 12-15 agent-days in all, of which the ZigGEM refactor is the largest part (§8).

## 1. What exists, and why a bypass rather than a bigger picture

The board composites each frame into an 800x280 picture of `{0,B,G,R}` words in DDR (`zm_video_comp`,
plane-major, at its own speed), then scans the previous picture out. `zm_vtiming` shows each of the 280
raster lines twice in the 800x560 middle of an 800x600@60 output (40 MHz pixel clock, 20-line bars).
`zm_video_scanfetch` reads one 400-beat line into one of two 48-bit display buffers
(`zm_video_dcram`, the clock crossing). `zm_video_scan` shows a line only if its buffer holds it.
Otherwise it shows black and sets the sticky `underrun` flag.

A 640x480 picture does not fit that frame. Three ways to show it:

| Option | What | Verdict |
|---|---|---|
| A. A taller picture | Pictures of 640x480 u32 (1.2 MB each, two), 480 composited lines a frame | Rejected. It doubles FRESCO's per-frame work (480 PLANE passes ≈ 1 Mc+) for a mode that needs no compositing, and needs a second picture geometry everywhere |
| B. Reuse the painter at scanout | Drive `zm_video_fetch` + `zm_video_paint` (they already make a 640-px medium line through the palette) a line ahead of the beam | Rejected. It puts the compositor on the beam's deadline, which FRESCO_OPTIONS "Decision 2026-10-24" refused, and it changes `zm_video_comp` |
| **C. Direct scanout of plane 0** | The scanout fetch reads plane bytes, the lookup happens in the pixel clock on a palette mirror | **Recommended.** Smallest LUT count, compositor untouched, one plane is all GEM needs |

C is TRUECOLOR_PLANE.md's "Option B" (costed there at 150-300 LUT and not recommended), applied to a
whole screen mode. The objections there were tearing, a picture that no longer equals the PFB, and the
2026-10-24 decision. Here they are answered in §3, §6 and §5. The frame-serial decision is about
compositing. Desk mode composites nothing, so the scene_hash oracle keeps a defined meaning (§6).

## 2. RTL: the blocks and their changes

### Palette lookup: where it goes

The display buffers carry RGB pairs today. An 8-bit plane needs 256 lookups somewhere:

- (a) in the compositor's clock, inside scanfetch, with a line FIFO and an 8:1 serialiser (Option B's
  pattern: est. 60-80 LUT for the serialiser, plus a buffer, plus a second read port or a mux on
  `u_comp`'s palette RAM, which changes `u_comp`);
- **(b) in the pixel clock, chosen.** Raw index beats go into the display buffers. A mirror of palette 0
  (256 x 24 bits) is a second `zm_video_dcram`, written from the snoop in the compositor's clock and
  read in the pixel clock. That is the same crossing the display buffers already make, so it needs no
  new synchroniser. `u_comp` is untouched.

### Per block

| Block | Today (Vivado, `board_v5fpu_budget.md`) | Change | Est. LUT |
|---|---|---|---|
| `zm_vtiming` | 75 LUT | `desk` input. Desk geometry: raster lines 60..539 shown ONCE (`zm_line = ny - 60`, 9 bits holds 479), `zm_active` also needs `80 <= nx < 720`, `zm_x = nx - 80`; `zm_hbl` on every output line of the raster (not every other one); `zm_vbl` at output line 540, not 580. The VESA 800x600@60 timing itself does not change, so the HDMI sink never resyncs. `desk` is latched at `zm_vbl` | +25-40 |
| `zm_video_scan` | 27 | Desk read address `{line[0], x[9:3]}` (beat), then the byte `x[2:0]` of the 64-bit word, then the mirror lookup, then the registered RGB: 2 more stages. **The syncs are delayed by the same 2 stages in both modes**, so the wire latency the TMDS / `video_out_tb` tests pin changes once, to one new constant. The free logic holds as is: `freed[!hbl_line[0]]` at each HBL and `freed[1]` at the VBL, because 479 is odd like 279 | +30-50 |
| `zm_video_scanfetch` | 58 | Desk: request length 80 (not 400), last beat 79, last line 479 (not 279), row address `desk_base + y*640` (`y<<9 + y<<7`) from a desk base latched at the VBL, not `fbase + y*3200`. The beat goes in whole (64 bits, no `{[55:32],[23:0]}` repack) | +30-50 |
| `zm_video_dcram` (display, `u_disp` in `zm_video_out`) | 1 RAMB36 + 1 RAMB18 (1024 x 48) | `DW` 48 → 64, so one beat is one write (beats arrive with no back-pressure, and two 48-bit writes a beat would need a skid buffer). Normal mode uses bits [47:0] | +1 RAMB18-equiv. |
| palette mirror (new `zm_video_dcram` instance, AW 8, DW 24) | — | Written when a snooped palette store hits plane 0's 256 words (`cpu_sel` palette bit, `cpu_waddr` in plane 0's range); read by the scan. A byte store to a palette word is legal (`u_pal` honours `cpu_be`), so the mirror needs byte enables too: three 8-bit lanes (`zm_video_dcram` gains a `be` port, or three instances) | +1 RAMB18, ~10 LUT |
| desk registers in `zm_video_out` (new, beside the snoop) | — | A copy of `RESOLUTION` (`== RES_DESK` → `desk_req`) and of plane 0's `FB_BASE`, taken from the snoop. The bus address `vbase + FB_BASE[0]` is computed once at the VBL, not per line | +45-70 (a 32-bit add, 40 FF) |
| CDC for `desk` | — | `desk_req` (comp clock) → 2 FF → `zm_vtiming`, latched at `zm_vbl`. The latched level → 2 FF → comp clock, where scanfetch samples it 4 clocks after its synchronised `vbl` (the pulse and the level both take 2-3 clocks: the wait makes the order certain). It changes at most once a frame and then holds for >10 ms | +5-10 |
| **mode total** | | | **~150-230 LUT, 2 RAMB18, 0 DSP** |
| hardware pointer (§4) | — | 16x16 mask + data, 2 colours, in the pixel stream beside `zm_glass_osd` | +60-100 |

`FB_BASE` must be 8-byte aligned in desk mode (a beat). The sealed machine renders from
`FB_BASE & ~7`, so a misaligned base looks the same on both machines. ZigOS allocates it 64-aligned
anyway (a 16-beat burst).

**Byte order.** A beat's byte 0 (`rd_rsp_data[7:0]`) is the leftmost pixel. Palette words are RGBA
little-endian, so the mirror keeps bits [23:0] = `{B,G,R}`, the order the scan already outputs. Alpha
is ignored in desk mode, and the machine writes A = 255.

### Clocks and the deadline (PERFORMANCE_REVIEW §2.4)

A desk line is shown once, so line `y+2` (same buffer as `y`) must be in by the HBL after the one that
freed it: **one** output line, 1,056 pixel clocks = 26.4 us = 3,300 comp clocks at 125 MHz. Today it
is two lines for 400 beats. §2.4's table scaled to 80 beats (5 bursts of 16):

| DDR condition (§2.4's per-burst figure) | Today: 25 bursts, 2 lines (52.8 us) | Desk: 5 bursts, 1 line (26.4 us) |
|---|---|---|
| idle, 40 cyc | 10.0 us | 2.0 us |
| moderate, 71 cyc | 17.8 us | 3.6 us |
| heavy (CPU + 3 planes + blit), 113 cyc | 28.3 us (§2.4 rates it against 26.4: FAIL) | 5.7 us |
| saturated, 186 cyc | 46.5 us | 9.3 us |

In desk mode the compositor issues no row I/O, so the scanout competes only with the cart CPU (HP0)
and CHISEL (HP2). A desk underrun needs 3x the saturated latency. The 60-line top bar gives lines 0
and 1 more than 1.5 ms after the VBL.

**Bandwidth:** 640 x 480 x 60 = **18.4 MB/s**, against 53.8 MB/s of scanout today plus the
compositor's row I/O (tutorial, one plane: 3.39 MB a frame, 203 MB/s). The DDR3 peak is 2,133 MB/s.

## 3. Tearing (Matt to decide; recommendation: accept)

**Superseded 9 Nov 2026** (Matt on the board: the screen blinked every time the mouse moved). The
desktop repaints whole frames, so the half-drawn one was on the screen. GEM now double-buffers the
desk: the shell allocates a second desk buffer (`zg.deskBuffer`, 614 KB of the pool for the pair) and
hands both to the ROM (`deskSetBuffers`, system table 1.15); a drawn frame goes into the buffer
FB_BASE does not show and FB_BASE moves to it when the frame is whole (rom/gem/desktop/deskflip.zig);
a clean frame draws and flips nothing. The firmware starts the frame after a flip only once the VBL
has taken it (cycles/bdesk.c), so the next frame never draws into the picture being scanned. No pool
room for the second buffer: the desk stays single-buffered. The text below is the original study.

The scanout reads plane 0 **live** while the cart draws into it. The browser shows the plane as it
was after `frame()`. The board can therefore show a half-drawn redraw for one frame where the browser
never does. That is how TOS worked: GEM drew straight into screen RAM while the Shifter read it.
GEM's incremental dirty-rect drawing (`deskdirty.zig`) suits a single buffer and would make double
buffering awkward (every change drawn twice). Recommendation: accept it and document it as the
mode's ST behaviour. A cart that wants no tearing (a TUI repainting the whole screen) can use two
buffers (614 KB of the 1 MiB pool) and flip `FB_BASE`, which the board latches at the VBL. The edge
case: a flip made late in a `frame()` that overruns the VBL waits a frame on the board. A palette
write made mid-frame belongs to the same class: the mirror updates live, so the board shows it from
the line being scanned, while the browser shows it from the next frame. No hash can see either.

## 4. The pointer: a real gap

**Decided 9 Nov 2026: option 2, GEM draws its own pointer** (no LUT for option 3: the slices are at
100 %). With two buffers (§3) there is no save-under problem: a pointer move is a touch, which redraws
the whole frame, and the arrow is drawn last (rom/gem/desktop/deskarrow.zig, TOS's ARROW form from
bcursor.c, white mask, black data). Only in the desk: in low and medium the hosts still draw it, and
GEM does not export `drawsOwnPointer` (the board tests that export's presence, so GEM would lose its
low/medium arrow). The page hides its cursor for any cart in the desk (the board draws none there).
The text below is the original study.

Today `cycles/bcursor.c` draws GEM's arrow into the back picture after compositing, and the next
composite erases it. Desk mode has no picture. The options:

1. **Save-under in plane 0** (firmware, no RTL). It breaks: either the arrow is missing while the
   cart's `frame()` runs (flicker, since the scan reads live), or the arrow sits in the plane while the
   cart draws over it and the save-under goes stale (TOS's `M_OFF` problem, which ZigGEM does not do).
2. **GEM draws its own pointer** (`drawsOwnPointer`). It has the same save-under issue, inside the
   cart, plus a cost every frame.
3. **A hardware pointer, recommended.** 16x16, mask + data, white and black (TOS's ARROW form, the
   bitmaps in `bcursor.c`), merged into the pixel stream after the scan and before the OSD. Glass sets
   its position from evdev directly (it already computes the pointer word), and it is hidden when the
   cart draws its own pointer (`input_arrow()`). It costs no cart time and has no erase logic. Est.
   60-100 LUT (two 11-bit position compares, a 16x32 LUTRAM pattern, a 24-bit mux). It can serve
   every mode later. In v1 it is used only in desk mode, and the other modes keep `bcursor.c`.

**Glass** (`fpga/glass/src/mouse.zig`): `MAX_X`/`MAX_Y` are compile-time 800x280 and `REL_Y` is
halved (doubled lines). Both become mode-dependent: desk is 640x480 at 1:1, with no border offset.
Glass needs to know the mode. It can read a desk bit that the firmware publishes in its video status
word (`map_cart.zig` `VSF_*`), which is the cheapest option, or `REG_RESOLUTION` through devmem.
`PTR_COORD_MASK` (10 bits) already holds 639 and 479.

**Does glass read the frame?** No. The OSD (`rtl/glass/zm_glass_osd.v`) is drawn over the pixel
stream in the PL, after the scanout, so it works unchanged in desk mode. Its position is in 800x600
output coordinates. Only `tools/board_pic.py` reads the pictures (§6).

## 5. ABI: what a cart sees

- `RES_DESK = 3` in `machine/sdk/memmap.zig` and `sdk/hardware.zig`. **HW 1.17.0** (additive, a minor
  bump): HW_API §3's `RESOLUTION` row, and a "Desk mode" section with the rules above.
- `hwInit` already writes `RES_PLANES`, so every boot, chainload and swap leaves desk mode. No new
  code is needed, but a test should pin it.
- In desk mode the machine ignores `FB_STRIDE`, `FB_MODE`, `HSCROLL`, `PLANE_ENABLE` above plane 0,
  every HBL id, `FB_COPPER`, `BEAM_COUNT` and `RES_FLICKER`. `FRAME` still counts. On the board, the
  firmware stores `FRAME + 1` itself, because no BG pass runs to do it.
- **Capability.** `hwVersion()` is the wasm's, so a 1.17.0 cart on an older bitstream would show
  garbage. Add a machine export `hwDeskAvailable()`: 1 in the browser and the native host, and on the
  board the firmware's answer from a PL feature bit in the video status. Cards with an older
  `system.rv32` refuse the cart through the existing `card_abi_check`. ZigOS's
  `zg.setDeskPlane()` returns an error when the capability is missing. ZigGEM then falls back to
  medium and shows an alert (DEVPAC_GAP §3b item 4).
- ZigOS: `fb.setDeskPlane()` (plane 0 only, a twin of `setMediumPlane`) sets `RESOLUTION`, allocates
  307,200 B 64-aligned, writes all 256 entries of palette 0 (which also refreshes the mirror after any
  copper use), and clears the plane. `setDeskPlane` / `setResMedium` switch back and forth.

### The VRAM pool and a `vramAlloc` guard

The plane takes 307,200 of the 1 MiB pool (`VRAM_BYTES`). That leaves ~740 KB, enough for a second
buffer, but not with anything big. `vramAlloc` (`libs/zig/zigos.zig:179`) has no guard. `vramWords`,
seven lines below it, does: it returns `null` when `off + n*4 > OFF_VRAM + VRAM_BYTES`. The fix models
`vramAlloc` on it (`?usize`, an alignment argument). It needs a native test (fits / exactly full /
one byte over) and a break test (with the guard removed, the over-allocation must corrupt
`OFF_PFB`). This fix is independent of desk mode and worth landing first.

## 6. The browser, the native host, the harnesses

**The sealed machine** (`machine/video.zig`, a new `video_desk.zig` under 200 lines): in desk mode
`clear()` only increments `FRAME`, and `renderPlane()` returns at once. `hwRenderDesk(half)` writes 240
rows of RGBA (A = 255) into the PFB: 614,400 B, which fits in its 896,000 B. A whole 640x480 RGBA
picture (1,228,800 B) does not fit, and the 8 MiB map is frozen (`sealed-loader.js:17`). New exports:
`hwDeskActive()`, `hwRenderDesk(half)`, `hwDeskAvailable()`.

**The page** (`docs/sealed-loader.js`): each frame, if `hwDeskActive()`, canvas 0 becomes 640x480
(CSS: centred, 1:1 in the 800x600 frame), canvases 1-3 are cleared and hidden, and two
`hwRenderDesk` calls each copy half into one ImageData. When the mode is left, the 800x280 canvases
come back. The pointer surface (canvas 3) takes the desk geometry, and `send()` maps it to 0..639 /
0..479 with no border offset.

**scene_hash.mjs**: a desk frame's hash is the tag `desk` followed by the two halves in order (the
`--composite` path is the same, since there is nothing to compose). **The native host**
(`fpga/cycles/main.c`, `fpga/host/kos_host.c`) has the same branch. **hp_sim** (`cycles/bmain.c`
`hash_plane`): a hashed desk frame calls the translated `hwRenderDesk` after `vseq_idle` and hashes
the PFB. So the cart + firmware are checked by hash, as for every other mode. The RTL's scan path is
proven separately on the wire (§7). The two proofs meet at the region dump. `tools/board_pic.py`
gains a desk branch that reads plane 0 and palette 0.

**The firmware sequencer** (`cycles/bmain.c` `frame`, `vseq.c`): in desk mode it skips `vseq_clear`,
`vplan_frame`, `bplanes_run` and `bcursor_draw`, and stores `FRAME + 1`. It then calls
`vseq_wait_swap()` and `vseq_present()`. The wait is required. Today the swap wait comes from the
first picture-writing pass (`d_ok`), and a second PRESENT before the VBL only keeps `pending` set
(`pending <= (pending && !vbl) || present`). Without the wait, a desk frame would run unthrottled: dt
would collapse, and hp_sim's frame numbering would drift from the browser's. With the wait, the swap
of two unused pictures at each VBL paces the frame, as `vseq_mix_only` already does.

## 7. Testing plan

| Level | What | Notes |
|---|---|---|
| RTL testbench | `video_out_tb` gains a desk scenario: a synthetic plane (a gradient + a 1-px checker + a distinct byte per beat lane) and palette, 2 frames on the wire, compared with the machine's `hwRenderDesk` output; the random memory latency of `video_mem.h` on every run. The scenario switches modes (normal → desk → normal) and expects whole frames of each and **zero underruns across both switches**. The only black frame is the one scanfetch already costs after reset ("waiting for a fresh VBL") | Seconds of CXXRTL, not an hp_sim |
| Break tests (`video_mutants.json`, `ZM_RTL_BREAK=1`) | each must fail the desk scenario: byte order reversed within the beat; lines doubled in desk; x not offset by 80; mirror written from plane 1's palette; `desk` sampled without the VBL latch (mid-frame switch); the old 400-beat length in desk; `--starve` (must underrun); the syncs not delayed (RGB two clocks early) | One per mechanism |
| Machine | native zig test of `video_desk.zig`: the two halves' seam at y 240, `FB_BASE & ~7`, A = 255, `hwInit` leaves desk, the other planes ignored; a break (`--break seam`: half 1 renders rows 0..239 again) | |
| Browser | `apps/desk_check.mjs` (named in `build.sh`): a tiny desk test cart, scene_hash in desk, the mode switch both ways, the pointer range; its `gate` line in the same commit | Long pixel proofs come from here, not the sim |
| Native host | `make -C fpga host-check` gains the desk cart | |
| hp_sim | one run, `--frames 6 --every 6`, of the desk test cart (a small cart: minutes, not hours), hashes = scene_hash = native | One lock, one cart |
| OOC synth | `fpga/tools/vivado_ooc.sh` on `zm_video_out` before and after, for the real LUT number (the estimates above) | The lead's or a timing agent's |
| Board | the lead uploads; Matt checks the desktop at 640x480, the arrow, a mode switch, and OSD F11 underrun = 0 | |

## 8. ZigGEM and effort

ZigGEM's changes are DEVPAC_GAP §3b's five abstractions: one `Screen` description, font metrics as
data, pointer mapping in one place, plane allocation by mode with the capability, and a third
DESKTOP.INF `#E` code (02) with window rectangles clamped on load. They include replacing the 9
hard-coded `200`s (`rom/gem/gui/window.zig`, `rom/gem/desktop/` `deskwin`, `deskdraw`, `about`,
`prefs`, `trash`, `info`, `filesel`) with `g.screen_h`, and `apps/zig/scenes/gem_desktop.zig`'s
pointer mapping, which keys on `desk_medium` today. The 8x16 font (GEM5 P2.5) is not needed for v1:
8x8 at 1:1 gives 80x60 cells.

| Part | Agent-days |
|---|---|
| RTL: vtiming, scan, scanfetch, dcram width, mirror, desk registers, CDC | 2-3 |
| RTL testbench scenario + 8 break tests | 1-1.5 |
| Hardware pointer (RTL + test + break test) and glass mouse mode | 1.5-2 |
| Firmware: desk frame path (with the swap wait), FRAME, hash, capability bit | 1 |
| Machine `video_desk.zig` + exports + tests, HW_API / HARDWARE_SPEC / gen_docs, HW 1.17.0 | 1-1.5 |
| Page + scene_hash + native host + `desk_check.mjs` + test cart | 1.5 |
| ZigOS `setDeskPlane` + `vramAlloc` guard | 0.5 |
| ZigGEM: the five abstractions, the 9 literals, DESKTOP.INF, the fallback alert | 3-4 |
| OOC numbers, a 6-frame hp_sim, board bring-up (lead) | 0.5-1 |
| **Total** | **~12-15** |

### As built (phase 2b, branch `feat/gem-desk-ziggem`)

- **Screen** (`rom/gem/gui/screen.zig`): `Gui.screen` holds w, h, stride, the mode and the font;
  the ROM sets it when it binds the plane (`rom_main.zig` `screenOf`: the mode from
  `RESOLUTION`, the stride 640 in the desk whatever `FB_STRIDE` holds) and on `deskSetScreen`.
  `types.zig`'s `MENU_H` / `CELL` / `ITEM_H` are the 8x8 font's `Metrics`; the nine 200s are
  `screen.h`, `centreX/Y` and `workArea()`.
- **Pointer, one place:** `deskHostPointer(x, y, buttons)` (appended export) takes the host's
  coordinates and maps them by the mode (`Screen.fromHost`: low halves x); the shell forwards.
- **Plane by capability:** the shell (`gem_desktop.zig`) takes the desk's 307,200 B once when
  `hwDeskAvailable()` says so and runs LOW and MEDIUM on its first rows, else the medium buffer;
  it tells the ROM (`deskSetDeskAvailable`), and Set Preferences greys Desk without it.
- **Mode change** (`rom/gem/desktop/deskmode.zig`): every window, its full-box rect and each
  directory's remembered rect are clamped into the new work area; an icon on the old bottom row
  keeps the bottom row (the trash).
- **DESKTOP.INF:** Save Desktop writes `#E 02` in the desk. At boot the shell reads A:'s
  DESKTOP.INF off a .zmd (`zg.disk`) and hands it to `deskLoadInf`, which returns the `#E` code
  (no desk on this machine: low res) and keeps the icons and A:\'s window for the next
  `deskSetScreen`, so they land clamped to the mode it boots in; A:\ reopens where it was.
- **The blitter clip** (found here): CHISEL and the machine clip a stride-640 destination at 200
  rows, so the desk's fills stopped at row 199; the ROM bands them (`gui/bandfill.zig`).
- **Tests:** `apps/gem_desk_check.mjs` (+ 4 break tests); low and medium are pixel-identical to
  the ROM before (scene_hash, gem_headless's 15 shots, a medium session); native tests of
  `screen.zig` and `deskinf_read.zig`; glass `mouse_test.zig`; host-check gem + desk_test.
- **Left:** the arrow on the board in the desk (no picture for `bcursor.c`: §4's hardware
  pointer, Matt's call), DESKTOP.INF off a FAT floppy, Save Desktop to a real disk.

## 9. Risks, and what Matt must decide

**Risks**
- **LUT.** ~210-330 LUT with the pointer, on a board at ~95.7 % (90.3 % on 3 Nov plus CHISEL v2's
  +952). Timing closure gets harder near the top (sys WNS was +0.04 ns at 94 %). The estimate is from
  Yosys/Vivado block sizes and could be off by 50 %. The first step is an OOC run.
- **A wrong mode crossing** shows one black frame and sets the sticky `underrun` on every switch.
  The mid-frame-switch break test exists for this.
- **Tearing** on the board only (§3): the browser can never show it, and no hash can see it.
- **Pacing**: the desk frame path must wait for the swap (§6), or the cart runs unthrottled on the board.
- **A stale palette mirror** if a palette store bypasses the snoop. None does today. The copper
  writes `u_pal` directly but is off in desk mode, and `setDeskPlane` rewrites palette 0.
- **Older bitstreams**: a cart that skips the capability check shows garbage on them.

**Matt decides**
1. **Go / no go**, and **the payer** for ~200-330 LUT. Candidates: trim the hardware pointer (GEM
   draws its own pointer and accepts the flicker, −60-100); a ranked cut from the CHISEL v2 row; or a
   tools bitstream variant without a demo-only block. I found no free payer.
2. **Tearing**: accept (recommended) or require two buffers for desk carts.
3. **The pointer**: hardware pointer (recommended) or a software one.
4. **640x480 rather than 640x400**: 480 is the brief's. It replaces the 1 Nov 640x400 row; 400 would
   save 15 % of the bytes and nothing in RTL.
5. **Border colour**: black (this study) or `BACKGROUND` (+24 bits crossed, ~10 LUT).
