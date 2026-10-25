# KESTREL roadmap: done

The finished items of the KESTREL roadmap, newest first. The open items live in the roadmap
artifact's Roadmap tab (https://claude.ai/artifact/2V2LVaerVTnPpn2RbwHH2W). Moved here on
25 Oct 2026.

## Done 24–25 Oct

| Prio | Done | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P1 | 24 Oct | union_deltaforce at 60 fps | screens | Was 50.8 fps with FRESCO composing only the window and the cart at 1.56 Mc. Each merge pixel written once, one blit per band at scale ±1 (5aa7075e): 60.4 fps on the board. The model's miss is a per-cart CPI factor on branchy byte loops (ff473f1f) | zm-scene-optimizer |
| P2 | 24 Oct | mpp_truecolor: per-line palettes as copper lists | screens / FRESCO | The HBL palette copies became 3b lists (43c20cde): the CPU stores no palette a frame. Board: 4 PLANES 30 → 57.7 fps, pictures equal (799ebd8e), then 60.4 with the split | agent |
| P2 | 24 Oct | pure_hbl gate flake ("Text file busy") | gate | vmix and the memmap header are built once, under a lock, and renamed into place (1b2b1c96) | lead |
| P1 | 24 Oct | FRESCO 3a: pure HBL-handler planes join the line-major pass | FRESCO firmware / ABI | REG_FB_HBL_PURE (HW 1.8.0): a cart (openBorders, copper/linepal installers, setFrameBufferHBLHandlerPure) says which handlers are pure; the board runs them between the passes of one line-major group. 0 LUT. Board pictures equal the browser's (board_pic, 20 frames of 5 carts); gate pure_hbl replays every flagged cart in the board's order | lead · kestrel-engineer |
| P1 | 24 Oct | FRESCO 3b: the hardware copper list | FRESCO RTL / ABI | REG_FB_COPPER (HW 1.9.0): per-plane lists with ops PAL, PALREF, REG (HSCROLL), FLICK; WRITEBACK (op 6) puts the palettes back at frame end. zg.copper / zg.linepal compile to lists, tcb_colorshock's raster is a PALREF list. zm_video_copper 548 LUT + zm_video_palwb 69. The planner skips unchanged list lines and redraws a plane whose list changed | kestrel-engineer |
| P1 | 24 Oct | Board card: bitstream c72c58ca + system HW 1.9.0 | board | 15,684 LUT (89.1 %), every clock met with the Vivado directives "closure" (place AltSpreadLogic_high, phys_opt AggressiveExplore, route Explore), now `--vivado-directives closure`. system.rv32 HW 1.9.0 (sys table 1.2), 109 lean carts. Previous card: d649cd0e | lead |
| P1 | 24 Oct | Board boot sectors: sysinfo's wasm boot sector at cold start | firmware | A sandboxed wasm interpreter in system.rv32 runs a disk's boot sector on the board (bootsec, bbootsec); `--bootsec X.zmd` checks its picture against scene_hash.mjs | agent |
| P1 | 24 Oct | Jochen Hippel's Amiga .hip on BARD | machine / BARD | The .hip's own 68000 replay with an emulated Paula window ($DFF0A0–DF, DMACON, VPOSR/VHPOSR beam counter). supplex_fs2 plays 'shaolin title.hip'; hippel_musicdisk (cart 109) plays 10 tunes. The OSD shows BARD:HIP_68k | agent |
| P1 | 24–25 Oct | Misaligned sweep + no per-frame float | screens / libs | 57 carts rebuilt without misaligned accesses, zg.mem ≥ 4-aligned; frame_cost lists every misaligned site with file:line. Fixed point: gen4, tlb_spoon, noextra, union_intro, music | agents |
| P1 | 24–25 Oct | Cart passes: big_demo, noextra, union_intro, lockbuster3, skystrike… | screens | big_demo's jukebox draws its page once (cart 0.92 → 0.36 Mc); noextra re-ripped from the real RASTERS.ZIP; lockbuster3 2.12 → 0.93 Mc; swedish_newyear, cuddly, reps, rno_sodium, superscroller, stretchY runs | zm-scene-optimizer · lead |
| P2 | 24 Oct | raytrace_f32 refinement + OBJ sphere demo | screens | raytrace(_f32) refine in 16 passes; the OBJ demo's sphere with +/- resolution, S cycles the shading, 1–3 pick the object | agents |
| P1 | 23–24 Oct | New carts 104–109, Phenomena re-ported | screens | gnomes (104), hmdfac (105), replicants_arkanoid2 (106, CODEF 33), ANIMA (107: oldschool, the "KESTREL can do more" gag, tunnel, melt, knot, end), leonard_spirit (108), hippel_musicdisk (109). Phenomena re-ported from CODEF 560 | lead · agents |

## Done 21–23 Oct

| Prio | Done | Item | Area | Notes | Who |
|---|---|---|---|---|---|
| P1 | 23 Oct | Memory placement: music starts on time | firmware | ZIGGY's and BARD's wasm memory at a measured offset in a 4 KiB page (ZIGGY_MEM_SET 0x5c8, BARD_MEM_SET 0x640) so they stop thrashing the 4 KiB direct-mapped D$: dbug's music starts at 3.6 s (6.09 before), rno_natrium back to 60 | kestrel-engineer |
| P1 | 23 Oct | Cost model recalibrated; frame_cost --budget | tools | Fitted to the posted-store board: store ~2.3 cycles, memset ~2.3 a word, palette writes ~free, misaligned trap ~210, f32 add/mul 9–10, CHISEL ~800 fixed a blit; 60 fps knee 1.75–2.1 Mc. --budget = cart + FRESCO passes against the frame | agent |
| P1 | 23 Oct | Plane merges: the FRESCO-bound carts | screens | supplex_fs2 3 → 1 plane, fallen_angels 3 → 1, ancool 3 → 1, tcb_colorshock 2 → 1, union main screen 3 → 2, stcs's logo on the scroller plane, union_deltaforce composes only its window | zm-scene-optimizer · lead |
| P1 | 23 Oct | Optimizer pass on the slow carts | screens | mentalhangover and grodan_kvack at 60; chonchon/chonchon2 compose with CHISEL; union_superscroller misaligned accesses 1,571 → 8 a frame; snyd_90 / swedish_newyear without misaligned longs | zm-scene-optimizer |
| P1 | 23 Oct | union_main retired; Union Demo: one intro + working doors | screens / glass | The main screen is the end of union_intro (60 fps). The Union Demo cart opens with The Carebears' credits and its doors boot the real screens (cart-to-cart swaps on the board) | lead |
| P1 | 23 Oct | STE DMA sound | machine / BARD | Frame-end latch, MFP Timer A event + GPIP7, Microwire volume: 110 of 122 DMA SNDHs play (77 before) | worker |
| P2 | 23 Oct | Play a song from memory on the board (sfx op 8) | BARD / firmware | zg.requestSongBytes plays an SNDH or a SAP from the cart's memory on the board too (sysinfo's SOUND page) | — |
| P2 | 23 Oct | glass: the frame budget on the OSD | ZWINDOW | F11's second line: cart Mc, FRESCO Mc, planes, % of the frame, missed VBLs; Shift+F11 opens the frame-budget page | lead |
| P2 | 23 Oct | Screen follow-ups from 20 Oct | screens | IK+: F1–F5 play Eliminator's five subtunes; union_intro's WAB walks its runs; stcs ZIG mode (Z) | agents |

## Done 20 Oct

| Prio | Item | Area | Notes | Who |
|---|---|---|---|---|
| P1 | The board's tube is black | FRESCO RTL | Bitstream d649cd0e (15,040 LUT): where every plane is transparent the board showed the mixer's #121010; now black, board and browser equal pixel for pixel | kestrel-engineer |
| P1 | Planar engines → chunky CHISEL blits | screens | lockbuster2 ~22 → 60 fps, stcs 48 → 60 on the board, pixel-exact | zm-scene-optimizer |
| P1 | scrolllab every mode under the frame | screens | Modes 3–6 and 9: est. 1.6–2.0 Mc, no float a frame, pixel-exact | zm-scene-optimizer |
| P1 | DMA intros and drafts on their real SNDH | screens / BARD | chonchon, larcociel2/5, phenomena, chonchon2, IK+, union_intro Androids: played by BARD instead of YM dumps | lead |
| P1 | New carts 99–103 + vex ZIG mode | screens | ikplus, chonchon2, lockbuster3, phenomena, mentalhangover; vex Z opens the side borders; Emlyn ZIG rasters through the top/bottom borders | lead · agents |
| P2 | SAP load overwrite hazard | audio module | A SAP load abandons a playing SNDH first | — |
| P2 | glass: F11 shows BARD's load; Page Up/Down | ZWINDOW | "FPS 60.0  BARD SNDH nat 43%"; Page Up/Down page the shelf | lead |

## SoC optimisations (KESTREL), done before 20 Oct

| Prio | Item | Area | Notes | Who |
|---|---|---|---|---|
| P1 | Posted stores on ZIGGY (8 writes in flight on HP0) | ZIGGY / HP0 | Bitstream 3ebb7381 (+157 LUT). A store 18 → 2.25 cycles; memset 4.5 → 0.56 c/B; 23 carts faster, none slower | kestrel-engineer |
| P1 | CHISEL call overhead halved | CHISEL / firmware | 8x8 fill 1,222 → 911 cycles. Bursts tested: no gain | worker |
| P1 | Word-wise memset/memcpy in the system | firmware | picolibc's rv32 versions were byte loops: −15 to −48 % on store-heavy carts | Fable |
| P1 | Dirty-line compositor + adaptive bypass | FRESCO / firmware | Only changed lines are recomposited; medium_overscan back to 59 | kestrel-engineer |
| P1 | FRESCO probe + bench cart | tools | Per-frame wait/pass counters in glass ctl stats; ZIGGY bench (113 tests) → fpga/BENCH_REPORTS.md | kestrel-engineer |
| P1 | 64-bit row writes on HP1 (W64) | FRESCO / HP1 | 0 LUT. HP1 must be 64-bit from boot; board default since 19 Oct | kestrel-engineer |
| P1 | Line-major compositing for handler-free planes | FRESCO | Bitstream 6261127d. 4-plane frame 3.42 → 1.13 Mc; leonard 30 → 59 | kestrel-engineer |
| P1 | A redrawn plane costs 1.17 Mc | FRESCO | Now ~0.19 Mc per extra plane with line-major + W64 (19 Oct) | kestrel-engineer |

## Cart optimisations and platform, done before 20 Oct

| Prio | Item | Area | Notes | Who |
|---|---|---|---|---|
| P1 | Pass 2/3: ics, equinox, tex, naos, tcb_weirddream, superscroller, gen4… | screens | ics 8 → 60, equinox 20 → 60, tex 28 → 60, naos 8 → 52, weirddream 23 → 56, superscroller 0.6 → 60 | worker · zm-scene-optimizer |
| P1 | Misaligned-load traps found and removed | screens / perf_audit | ics (~12 K traps/frame) and naos (~23 K); perf_audit flags them | worker |
| P1 | Native BARD interrupt drivers (8 digi tunes) | BARD | Thalion Forever 308 % → 79 %; dbug, snyd_90, tcb_spreadpoint, Swedish New Year, B.I.G. | kestrel-engineer |
| P1 | Audio mirror BARD → ZIGGY (sys table 1.2) | BARD / ABI | dbug moves on the beat again; music_debug's YM scope works | worker |
| P2 | Black borders and a black tube | ZigOS / FRESCO | ZigOS default + board BACKGROUND; black tube since d649cd0e | — |
| P1 | Lean carts (#127), XM on BARD, ST Replay, joystick, FPU F-key | board | On the board since 17–18 Oct | kestrel-engineer · worker |
| P2 | SysInfo (HWAM 8.34 look) | GEM app | 5 pages, GEM menu, speed tests vs a stock ST | — |
