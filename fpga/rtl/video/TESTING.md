# `rtl/video/`: how it is tested

```sh
uv run pytest -q tests/test_rtl_video.py                   # the replays and oracle checks, ~1 min
ZM_RTL_BREAK=1 uv run pytest -q tests/test_rtl_video.py    # + the 25 break tests, ~5 min more
uv run python tools/video_dump.py tutorial 300             # record frames of a cart
uv run python tools/video_dump.py --synth beam             # record a synthetic scenario
uv run python tools/video_rtl.py build/vdump/tutorial/frames 300   # replay (video_cover.py: coverage)
uv run python tools/video_rtl.py --timing 24 build/vdump/tutorial/frames 300 # clocks, 24-clock memory
uv run python tools/video_rtl.py --out 5:2 build/vdump/tutorial/frames 300   # whole frames on the wire
make -C fpga video-sim                                      # the integration test (below), ~1 h
ZM_CHROME=1 uv run pytest -q tests/test_video_mix.py       # the picture model vs headless Chrome
uv run python tools/video_order.py union_main 300          # would line-major HBLs change the frame?
```

1. **Record.** `tools/video_dump/vdump` is the native host (`fpga/host/`'s
   machine, ROM and cart objects) plus a recorder. Every `hblDispatch` and every
   pass is bracketed by a delta record of the registers, palettes and BEAM table;
   it saves the memory the fetcher reads and the PFB after `hwClear` and after
   each enabled plane. `vsynth` is the same recorder around `machine-video`
   alone, programmed by C scenarios (`vsynth_scen.c`), which reaches what no cart
   does. The machine still renders those frames.
2. **Replay.** `tests/tb/video_comp_tb.cpp` (CXXRTL) runs the frame in the
   machine's order: a BG pass for every line, then LATCH and a PLANE pass for
   every line of each enabled plane (a MIX pass a line when none is), then
   PRESENT, against a memory that accepts and answers bursts on random clocks
   (`video_mem.h`). Before a pass it writes, through the CPU port, each word that
   differs from what the machine held for that pass and line. After it, it
   compares the PFB row the pass left in memory with the machine's (the dump's
   own PFB is poisoned first, so every row must come from a pass). The words the
   compositor writes itself are checked against the machine's next record, never
   overwritten unseen. The picture the frame built must equal the browser's
   (`f<N>.mix`, from `tools/video_dump/vmix.c`). `tests/tb/video_out_tb.cpp`
   then plays whole frames through `zm_video_out` (both pictures of the double
   buffer, swapped at VBL) and checks every pixel clock of RGB/DE/HSYNC/VSYNC on
   the wire against the frame the swap count says is shown, so a torn picture fails.
3. **The oracle is untouched:** every cart frame's dumped PFBs hash to what
   `fpga/host` reports for that frame.
4. **Each frame states what it exercises** (`video_cover.py`, from the records:
   modes, and the effects a handler actually changed), and fails if it stops.
5. **Break tests:** 49 one-rule mutations of the RTL (`tests/tb/video_mutants.json`),
   each with the dump that must catch it; a hung pass is reported, not waited
   on. Opt-in (`ZM_RTL_BREAK=1`). All 49 caught on 2026-10-02 (the compositor,
   the row I/O and pass phases, the mixer, the double buffer and the scanout;
   `tests/test_rtl.py` adds 5 for the TMDS encoder).
6. **The integration test** (Fable #9, `tools/video_sim_run.py`, `make -C fpga
   video-sim`): the cart CPU (VexRiscv in Verilator, `soc/video_sim.py`) runs a
   translated cart with the firmware sequencer (`cycles/vseq.c`), the RTL
   pipeline composites into main RAM, the scanout shows it in the pixel clock,
   and both masters go through the board's memory-path model into one shared
   RAM. The PFB hashes must equal `apps/scene_hash.mjs`'s and the native host's,
   the scanout must never underrun, and the sequencer built in the line-major
   order a beam-racing compositor would impose (`ZM_LINE_MAJOR`) must fail on
   badflicker and equinox. The no-drain and no-copy-back builds run too and are
   reported; they survive the corpus (README "Integration" says why).

## Coverage: proven or not yet

"Proven" means at least one replayed frame matches the machine pixel for pixel
in every pass, and a break test of that rule is caught.

| Mode or effect | Status | Evidence |
|---|---|---|
| normal mode, static palette | **proven** | `tutorial` 300, `union_intro` 100 |
| 2–4 planes layered over the background | **proven** | `union_main` (3 planes), `tcb_colorshock`, `union_l16`, synthetic `layers` (4 modes stacked) |
| fullscreen (`FB_MODE_FULLSCREEN`), fine scroll latched, odd stride, `hs > stride` | **proven, synthetic only** | synthetic `fullscreen`. ZigOS no longer sets mode 1, so no cart reaches it. |
| legacy fullscreen (mode 0, stride 400) | **proven, synthetic only** | synthetic `fullscreen`, plane 2 |
| overscan, borders opened on time | **proven** | `union_main`, `replicants_emlyn`, `gen4_3615`, `maxi`, `fullscreen` (cart) |
| overscan, mistimed flicker (noise) | **proven** | `badflicker`, synthetic `overscan` (late HBL, tolerance edge) |
| overscan with a wider buffer (stride 512) | **proven** | `tcb_colorshock`, synthetic `overscan` |
| scroll mode (pan by `FB_BASE`) | **proven** | `scroll` 300 |
| scroll mode, `HSCROLL` per line | **proven, synthetic only** | synthetic `scroll`, `layers`. `scroll_demo`'s distort needs a key press. |
| medium, `RESOLUTION` per line | **proven** | `res_switch`, synthetic `medium` (including `RES_TRUECOLOR`, which renders as low) |
| medium overscan (stride ≥ 800) | **proven** | `medium_overscan`, synthetic `medium` |
| palettes changed per line by HBL (copper, linepal) | **proven** | `replicants_emlyn`, `gen4_3615`, `tutorial`, every synthetic scenario |
| `BACKGROUND` changed per line | **proven** | synthetic `beam`, `layers`; `dhs_0pxl0reg` 900 |
| BEAM lines: snapping, gap and x drops, more than 64 entries, carry into `BACKGROUND` | **proven** | `dhs_0pxl0reg` 300 and 900 (a static picture), synthetic `beam` |
| unaligned `FB_BASE`, `FB_BASE`/`HSCROLL` rewritten mid-frame (must be ignored) | **proven, synthetic only** | every synthetic scenario |
| a fetch stalled by the memory port | **proven** | random `ready` and latency on every replay (`ignore_ready` break test) |
| plane-major order: PFB rows to memory and back between planes | **proven** | every replay; `no_pfb_load`, `bg_rows_not_stored`, `mixed_rows_not_stored`, `row_address_3072` |
| row write-back through a stalling port (skid buffer) | **proven** | random write `ready` on every replay; `skid_overrun` |
| double-buffered picture, swap at VBL, no tearing | **proven** | `video_out_tb` on `dhs_0pxl0reg` and `s:worst` (2 frames each); `no_interlock`, `swap_without_vbl`, `scanout_shows_back` |
| scanout fetch starved | **proven** | `--starve 16` must underrun (`test_a_starved_scanout_fetch_underruns`) |
| the CPU, the sequencer and the RTL together, against scene_hash | **proven** | the integration test, 5 carts (`fpga/rtl/video/README.md` "Integration") |
| HBL handlers that write VRAM mid-render | **not yet** | The replay serves the pre-render image. `vram_changed` is 0 on every corpus frame. |
| the plane mixer: transparent, blended, no plane, 4 canvases | **proven** | `union_main`, `gen4_3615`, `dhs_0pxl0reg`; synthetic `alpha`, `bgalpha`, `worst`; picture model = Chrome's |
| picture rows loaded back for the next plane's fold | **proven** | `--timing 24` replays of 7 multi-plane keys; `no_picture_load`, `loads_swapped`, `picture_halves_swapped` |
| scanout: 800x600 stream, bars, two clocks (5:2, 15:4, 2:1) | **proven** | `video_out_tb` on `union_main`, `dhs_0pxl0reg` (2 frames), `worst`; 2:1 on `worst` must underrun |
| TMDS encoding | **proven** | 2 M symbols equal to a spec encoder, decode and DC balance (worst disparity 8) |
| fullscreen stride > 1021 | **not supported** | flagged (`overflow`) and not drawn. The machine has no such limit. |

