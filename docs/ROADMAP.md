# KESTREL roadmap: open work
**The source of truth for open work** (lead, agents, the worker session). Finished items move to
[ROADMAP_DONE.md](ROADMAP_DONE.md). Matt's view is the artifact (https://claude.ai/artifact/2V2LVaerVTnPpn2RbwHH2W),
regenerated from this file.
Rules (Matt, 31 Oct 2026):
- Update this file in the same commit as the work: a row when work starts, its status as it moves, and
  when it is done move it to ROADMAP_DONE.md with its commit.
- **Every unmerged branch has a row** naming the branch, its state and what landing it takes. Parked work
  stays here as "Parked" with the reason; a branch is never just left behind
  (`perf/chisel-queue-v2` sat 8 days built and board-measured but unmerged).
- **Forgotten-branch review** (Matt, 31 Oct): at the start of every lead session, and before any branch or
  worktree cleanup, list every branch with commits not on main and check each has a row here:
  `for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do n=$(git cherry origin/main $b | grep -c '^+'); [ $n -gt 0 ] && echo "$n $b"; done`
  (`git cherry` is patch-aware: a branch that landed rebased counts 0). A branch with no row gets one or
  is deleted, with a line in the commit saying which.
Status words: In progress · Pushing · Board A/B · Board check · Planned · Parked · Idea · Matt to decide.

## Open (31 Oct)

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P1 | In progress | CHISEL v2 | CHISEL RTL / machine | Branch `feat/chisel-v2` (the fold: -329 LUT so far). **First: land the QUEUE** (HW 1.8.0, command 5: a descriptor list, the CPU no longer spins on BUSY): built and board-measured on `perf/chisel-queue-v2` (20 Oct: small queued ops ×2.7, stniccc ×1.23) but never merged; rebase onto main + bitstream (Matt, 31 Oct: don't forget it). Then: step 1 the LUT cut (fold chk / halftone / triangle, ~850 LUT) + overlap from the real rectangles (in-plane copies at full speed); then AFFINE with a per-row table (Mode 7, rotozoom), MAP-GATHER (tunnels), mirror blits, a sticky collision bit, area fill, a command list (CPU/blitter overlap). See the CHISEL tab | kestrel-engineer |
| P1 | In progress | Fable ISA plan, steps 0-2 (Matt: GO 31 Oct) | ZIGGY | fpga/review/KESTREL_NEXT_ISA.md (on main, fd8461b8). Step 0 software libs (`feat/fx-libs-step0`: fx3d_fixed, texspan/texmap, fxrows); steps 1-2 BUILT on `feat/ziggy-dcache-zmx` (OOC + core sims, no bitstream): D$ 16 KB 2-way +61 LUT +2.5 RAMB36 (roto128 24.5 -> 13.0 c/px, voxel256 1.81 -> 0.92 Mc); ZM-X v1 (mulsh x2, tex2d, funnel x3, add8s/sub8s/avg8/add8) +223 LUT +37 FF 0 DSP, WNS +0.60 ns @100 MHz OOC, RTL = C twin = zmx.zig (test_zmx.py); twins in rom.wasm (sys ABI 1.5), ZM_ZMX cart images, trap fallback on old bitstreams. Next: the lead's combined bitstream (`make vexgen-zmx`, `--cpu-netlist build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v` first, `...Zmx.v` if sys misses 100 MHz), then the showcase carts. Step 3 (span AFFINE + MAP) is in CHISEL v2; step 4 BARD ops later | agents |
| P2 | Board A/B | Libraries: fills on the CPU, copies on CHISEL from 1 KB | libs | perf/chisel-policy: 116 carts pixel-identical, −2.46 Mc a frame summed (tsl_hybridglenz 0.37 → 0.15, anima 0.60 → 0.43, GEM GUI 0.13 → 0). Waiting for a board session | worker |
| P2 | Board A/B | Planner: PAL lists compared, copper records never skipped | FRESCO firmware | Branch `perf/pal-lists-compared` (the records fix is on main, bb92bfc6). 9a952fee (records on skipped lines were lost on the board: latent, no cart hit it) pushing; 3c7fe9f7 lets PAL lists skip unchanged lines (lockbuster2 480 → 53,432 skipped lines in 300 frames, fallen_angels, texcopier) | kestrel-engineer |
| P2 | Board check | dbug + cuddly_starwars | screens | On main (b4d4f3b2): dbug no longer copies inside a plane (est 2.07 → 0.83 Mc, was 33.5 fps), cuddly's raster on the copper, CPU clear, comptime fade (borderline 56-60). On the card, to measure | zm-scene-optimizer |
| P1 | Board A/B (needs the QUEUE bitstream) | CHISEL QUEUE reference: OBJ sphere, 3,968 faces, GLENZ | CHISEL | Matt, board 31 Oct: CHISEL 18 fps, CPU 15 (~5.5 Mc a frame, ~3.3 Mc of it the synchronous ~830-cycle call per face). GLENZ NEST shows no gap at 60 (59 CHISEL / 60 CPU): since posted stores the CPU fills as fast. Re-measure on the QUEUE bitstream | lead |
| P2 | Board test | Fetch-latency bench (plane interleave study) | FRESCO | Study: don't interleave planes (no gain without RTL, merging ≤0.04 Mc). The bench measures the real fetch latency to decide between a prefetch (0.05-0.08 Mc) or a 2-deep command (0.02-0.07), or neither | — |
| P1 | Open | tcb_colorshock: row 0 races | FRESCO firmware | Row 0, x 480..793, the blue byte differed from the browser (0xb4 for 0x98) at frames 150 and 600, boot to boot, under the plane-major firmware and 3a. Not seen since its raster became a 3b PALREF list: a board soak of a few minutes would close it. fpga/review/OPEN_colorshock_row0_race.md | kestrel-engineer |
| P2 | Planned | .hip music on the board | BARD | supplex_fs2 and hippel_musicdisk play Hippel's Amiga .hip in the browser; listen on the board and read BARD's load on the OSD | lead |
| P2 | Next week | Revisit bubblebobble + kickoff2 | screens | Parked by Matt 25 Oct for the week of 26 Oct. bubblebobble: polish the opencode port or re-rip from the real ST game. kickoff2: choose the Amiga or ST target and how far to take it. Gaps in prototypes/opencode_revisit/ | — |
| P2 | Paused | Scope mirror for MOD / XM / samples | BARD / ABI | fix/scope-mirror (18 Oct, does not build yet): BARD reads back the points CHORUS played, so the board's MOD/XM/sample scopes move | — |
| P2 | Planned | Scanout-underrun counter (review F2) | FRESCO | The video arbiter can't preempt a granted compositor row, so the scanout fetch can wait a full row. No underrun seen, but no per-frame counter to prove it. Double-buffer the scanout only if the counter fires | kestrel-engineer |
| P2 | Planned | The OS in the boot image (KESTREL's "TOS ROM") | ZWINDOW / KOS | Matt, 31 Oct: bake `glass`, `system.rv32` (POST, boot sector, GEM) and the KOS desktop into the rootfs / boot image, so the SD card needs only the boot files + the bitstream and the whole shelf is optional (floppies in the box). Ends the old-glass-after-reboot problem; a newer SD copy can still override for development | — |
| P2 | Planned | Board carts from any checkout (no pinned worktree) | board tooling | Matt, 31 Oct: `prototypes/cart_card.sh` (menu → rebuild one cart → both SD shelves) builds in the `board-lean` worktree because it holds the card's system build, so a cart newer than that worktree can't build. Set up `fpga/` in the main checkout once (tools, netlists, submodules, the bitstream's csr.json, the first sim/objects build: ~10-20 min), and check the cart/system table version against the card's `system.rv32` instead of pinning a commit; the system is rebuilt only when that version changes. ~1 h, most of it build time | lead |
| P1 | Pushing | sysinfo: XM and HIP on the SOUND page | screens | `feat/sysinfo-xm-hip` (1e606398 + guide regen); browser-checked by Matt 31 Oct | lead |
| P1 | In progress | KOS FAT12 (F1-F5) | ROM / ZWINDOW | `feat/kos-fat12`: see the KOS section row. Then `feat/kos-v2` (cartridge slot, tool cart doc KOS_TOOL_CART.md, Shift+F12 split) | KOS agent |
| P1 | In progress | OSD: MiSTer layout + F11 without paper | ZWINDOW / RTL | `feat/osd-mister` (glass on the board as the KOS test glass); the F11 no-paper RTL + shadow goes in the next bitstream | OSD agent (queued) |
| P2 | In progress | STNICCC 3D from PICONICCC data | screens | `feat/stniccc-3d`: the STNICCC 2000 flight as 3D data (Luis's pouet post) | agent (queued) |
| P2 | Queued (after CHISEL v2 + step-0 libs) | grodan_kvack ZIG mode: the KESTREL showcase | screens | Matt, 31 Oct (after a new STE megademo zoomed Grodan's pink carebear plane): the original stays untouched; Z switches on: the pink layer ROTOZOOMED (software spans first, CHISEL AFFINE on the new bitstream), overscan fullscreen, the green layer on its own hardware-scrolled plane (drawn once, FB base + HSCROLL), 24-bit copper rasters + per-line colour cycling of the pink layer, 2 more copies of the vertical scrolltext in the side borders (CHISEL keyed blits). Sprites unchanged (the carebears). No water; parallax maybe later. Stays at 60 fps | agent |
| P2 | Study, before the Falcon port | FRESCO true-colour plane mode | FRESCO / machine / ABI | Matt, 31 Oct: one plane in true colour, 16-bit 565 first (Falcon-like, half the bandwidth, 2 px a store), 8888 option. The cart writes the final format: no palette lookup / compositing, maybe scanout straight from the cart's buffer (~0.7 Mc saved). Measure the LUT, the machine/browser/ABI change, CHISEL 16-bit pixels; copper palette tricks don't apply | — |
| P2 | Later (after Fable's features on the board) | "Can KESTREL catch a Falcon?": Are You Sitting Comfortably? | screens | Matt's favourite intro (Reservoir Gods, Falcon 030, 2004, demozoo 74426; music MSG). The DSP does the 3D, many true-colour effects. First a how-was-it-done analysis (each effect: ZM-X mulsh + rcp + CHISEL spans for the 3D; per-line palettes, mpp planes or the true-colour mode for the colour), then the port | — |
| P2 | Planned (after the combined bitstream) | KESTREL SDK for outside coders | board tooling / docs | Matt, 31 Oct: a friend with a Z7-Lite wants to write demos without the SoC / Vivado. Zig 0.16 + ZigOS libs + SDK headers, the browser emulator for iteration, wabt `wasm2c` + xPack `riscv-none-elf-gcc` + the Python packers (Linux / macOS). Ship the generated files the first build makes with Verilator today (CSR header, memmap, cart runtime, sys ABI); version it with an SD-card release (bitstream + system + boot files); a tarball (or Docker) with a template cart, `make` / `make board` / `make floppy`, VS Code + ZLS settings. Before the Rick cracktro | — |
| P3 | Queued (moved down by Matt 31 Oct) | Rick Dangerous: Empire cracktro + trainer | screens | EMP_CABL.PRG (The Empire's Cabal cracktro, prototypes/cracktros/) patched for Rick: its look/music, the title changed, a trainer menu (infinite lives / bullets / dynamite y/n) setting Rick flags; replaces Matt's local hand edits; keep hud.zig's 6-icon cap | agent (after KOS) |
| P2 | Built, not measured | ZIGGY read bypass | ZIGGY RTL | `perf/ziggy-read-bypass` (19 Oct): cache refills overtake posted stores to other lines. Bitstream built 15,153 LUT (+108), sys WNS +0.074, CSR map unchanged; no board number recorded. Matters more now that every store is posted: Matt 31 Oct: merge if it shows a gain. Its only figure is the model (memcpy 2.78 -> 2.25 c/B, x1.24); never run in hp_sim or on the board, and it turns the bypass ON by default for the board and every sim. Rebase is clean (RTL; only decisions.md / handoff conflict). Plan: rebase, put it in the combined bitstream with the QUEUE, A/B (mc.lib.64K, a few carts), merge on a gain | lead |

## KOS: the KESTREL Operating System (ZigGEM in ROM), docs/ZIGTOS_BOOT.md

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P1 | Board test | Empty card boots to the desktop, like an ST | KOS / ZWINDOW | Matt, 31 Oct: with nothing on the shelf (only boot files, bitstream, glass, system.rv32) the board must POST and show the desktop with no A icon; a floppy (or F) brings the A icon. KOS v1's design, proven in the browser, not yet on the board | lead (next board window) |
| P2 | After v1 | ZigGEM improvements on KOS | GEM / ROM | Matt, 25 Oct: once KOS v1 boots, improve ZigGEM itself toward a real small desktop OS (scope to be set with Matt; the GEM follow-ups list in rom/gem is the starting point) | — |
| P1 | In progress | KOS v2: the cartridge slot and tool cartridges | ZWINDOW / ROM | A cartridge slot (`cart=`, Insert / Eject on the OSD). **Tool cartridges** first (Matt: the reason for the slot): a resident freezer / debugger on a hot key, on glass's side, never in the cart's memory: freeze ZIGGY, registers, memory and VRAM, planes and copper lists, BARD's state, frame breakpoints, resume. Its own design doc. Then the diagnostic cartridge (board self-test at power-on: sysinfo's tests, the bench) and application cartridges | — |
| P1 | In progress | KOS v2: AUTO and COMMAND | ROM / GEM | A data disk configures the OS: `AUTO.<n>.WSM` programs run before the desktop, `COMMAND.WSM` replaces it with a shell (TOS steps 27-28) | — |
| P3 | Planned | KOS v3: resident programs | ROM | TOS's reset-survival hooks (resvector, $200-boundary programs) as a declared ROM call whose routine runs in the boot-sector sandbox on a warm reset | — |
| P1 | In progress | KOS: FAT12 (GEMDOS-style) | ROM / ZWINDOW | Branch `feat/kos-fat12`: F1-F4 done (fd809356: the real floppy as drive A with `D`, .WSM programs off the floppy, the A icon only with a disk in, labelled FLOPPY / SD IMAGE). Next: F3b a floppy program carries its own rv32 (NAME.RV or a container, hash + ABI checked; the SD's progs/by-hash only as a fallback: Matt, 31 Oct, the floppy must not need the SD card), then F5 C: = the SD card read-only through a CART import `env.kosDriveRead` (Matt's choice, 31 Oct). The board paths compile, not yet run on the board | KOS agent |
| P3 | Idea | KOS v3: hard disk C: from SD folders | ZWINDOW / GEM | A hard-disk device in the drive ABI: SD card folders as C:, D:… in the desktop | — |
| P3 | Idea | KOS v3: desk accessories | GEM | Small programs in the Desk menu running beside the desktop (.ACC), and the control panel as the first one | — |

## FRESCO options (Fable review, 24 Oct: stay frame-serial)

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| — | Not opened | Composite at scanout (beam racing) | FRESCO | Would take all of FRESCO off the frame, but reverses the 2026-10-02 ADR, needs a cart ABI change (double-buffered LFBs), +800–1,500 LUT at 89 %, a hard per-line deadline (a slow line is on-screen garbage) and loses the scene_hash oracle | — |
| — | Parked | Overlap FRESCO with the cart | FRESCO / ABI | Frame = max(cart, FRESCO) instead of the sum, but needs carts that flip their LFBs (opt-in ABI), double-banked palettes and no plane handlers. If double-buffering is ever paid for, it is for this | — |
| — | Not now | RGB565 picture rows (review F3) | FRESCO | Only 24-bit packed rows are exact (the rows carry alpha); the gain is ~0.03 Mc a frame for 150–250 LUT | — |
| P3 | Last | More dirty-line skipping | FRESCO | Content-dependent, not deterministic (Matt): after everything else. The planner already skips unchanged lines with copper lists compared word for word | — |

## SoC optimisations (KESTREL), still open — measured with the native bench cart and the FRESCO probe

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P2 | Planned | Hardware dirty bitmap in the video snoop | FRESCO | The software row compares cost ~0.33 Mc per static plane; ~200 LUT. PLANES_PLAN.md rank 3 (LUT is tight at 89 %) | — |
| P2 | Planned | Misaligned access traps (~210 cycles) | firmware | Still ~20× a byte-wise access. The carts no longer pay it (24 Oct sweep: 57 carts, zg.mem ≥ 4-aligned; frame_cost names every site); left: a trap fast path or byte-safe codegen for align=1 loads | — |
| P3 | Planned | Per-line fill table / skip uncovered lines | FRESCO | −0.38 Mc on raster carts, −0.18 per non-first plane | — |
| P2 | Planned | W64 rewrites unchanged static rows | FRESCO / firmware | Marker test: 94 % of a static picture kept on W32, 0 % on W64 — the row skip may be off in 64-bit mode | — |
| P2 | Tested, parked | Reads wait for the store buffer to drain → read bypass | ZIGGY / HP0 | Built (perf/ziggy-read-bypass, +108 LUT): memcpy 2.74 → 2.47 c/B, only stcs moved in fps (and stcs is 60 now from its CHISEL rewrite). Not worth the LUT on its own | kestrel-engineer |
| P3 | Planned | I$ overflow costs ~4× per instruction | ZIGGY | 16 KB 2-way: big unrolled loops and large carts refetch; watch code size in hot paths | — |
| P3 | Idea | BARD async message queue (Matt, 31 Oct: "could be funny") | BARD / ABI | A ring of commands ZIGGY → BARD (play, stop, SFX, tempo, synth parameters) and events back (pattern row, loop, a beat), so neither CPU waits on the mailbox: music-synced effects without polling, and BARD as a real coprocessor (synth voices from Fable's step 4). Mostly firmware + ABI, little RTL | — |
| P3 | Idea | Raw memcpy DMA channel, 64-bit bursts | KESTREL | Could reach several hundred MB/s vs CHISEL's 77; ~300–500 LUT, hard at 89 %; only if perf_audit finds big per-frame copies | — |
| P3 | Idea | f64 still 200–560 cycles an op | toolchain | Soft-float; keep f64 out of the frame (CLAUDE.md rule), f32 on the FPU is ~10 cycles | — |
| — | Refused | Gemini review: invented tools, LUT diet, BARD on ARM, smaller BARD | review | See fpga/review/PERFORMANCE_REVIEW.md status table: made-up cart profiles, wrong Vivado row, stale FPU claim | — |

## Cart optimisations — shelf budget 25 Oct (109 carts, memcpy-aware model): none really under 60; only the FPU twins, union_intro (board 59.2 before its fix) and mpp_truecolor's 4-plane over-price

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P3 | Planned | Quartet (dune_gen4) at 117 % of BARD | BARD | A native interrupt costs ~6.9 k cycles; a hotter per-interrupt path | — |

## Platform

| Prio | Status | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P3 | Revisit | ST Replay: how INTERNAL output paces its feed | ST Replay / ABI | hostMicros pacing kept (17 Oct); options: real frame dt, a DAC FIFO flag, 60 fps | — |
| P3 | Planned | Ethernet (EMIO MII pins) for ssh | KESTREL | PS GEM0 through the PL to the RTL8201F | kestrel-engineer |
| P3 | Idea | BARD as a coprocessor | BARD | Frame-synchronised job API: 3D transforms, depacking, physics | — |
| P4 | Idea | 8 hardware PCM channels | CHORUS | +100–200 LUT; BARD's software mix preferred | — |
