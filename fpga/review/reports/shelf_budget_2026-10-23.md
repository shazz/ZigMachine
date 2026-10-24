# Shelf frame budget, 2026-10-23

Every cart of the docs/ shelf (108 with a disk; tree 733c8eaf = origin/main 51b237a1 + frame_cost --budget)
through `node apps/frame_cost.mjs --budget` and the plain estimate, in two windows: frames 721-1020 (the board
table's 12 s window) and 2401-2700 (40 s, a later phase); each cart's WORSE window is the one ranked. Scripted keys
as `CART_ARGS` (joust's game). Hot spots named from `tools/perf_names.sh` (file:line). Budget = cart + FRESCO, the
serial frame (fpga/review/reports/frame_budget_2026-10-23.md); a cart under 1.67 Mc is predicted 60 fps, and
1.67-2.1 is the knee band where the board's `missed` decides (docs/PERF_AUDIT.md).

**24 of 108 are predicted under 60 fps, 10 of them in the knee band.** 8 of the 24 ran 60 fps on the 10-20 board
table: board-verify those before dispatching (most are predicted slow only in the 40 s window, a later phase the
board table never measured; mpp_truecolor is a known over-price: the board's planner composes it in 200 passes,
the model counts 4 planes).

## Dispatch list (predicted slow, and slow on the 10-20 board or not measured there)

| # | cart | budget Mc (cart + FRESCO) | board 10-20 | lever | where |
|---|---|---|---|---|---|
| 1 | union_main (and union_intro, which runs it after 40 s) | 3.25 (1.27 + 1.98), 3 overscan planes | 34.1 ms | merge the 3 overscan planes (-1.44 Mc of FRESCO); then 250 tiny CHISEL blits a frame (0.84 Mc) | dragonball_squash.zig:46 |
| 2 | stniccc | 3.09 (2.55 + 0.54) | 22.1 ms | 1,649 CHISEL fills a frame, mostly tiny (1.71 Mc of waiting; ~800 cycles fixed each): CPU spans for small polygons, CHISEL only for big ones | gpu.fillRect via polyfill.zig:103 |
| 3 | phenomena | 2.82 (2.28 + 0.54) | not measured | byte stores in the DNA loop (0.89 Mc) and the logo redrawn unchanged every frame (0.40 Mc): draw it once | dna.zig:199, app.zig:203 |
| 4 | music (music_debug) | 2.70 (2.16 + 0.54) | 25.4 ms | cart side: logo.draw 0.68 Mc + a sine routine 0.31 Mc (a table) | music_debug/logo.zig:109 |
| 5 | supplex_fs2 | 2.58 (0.60 + 1.98), 3 overscan planes | 33.2 ms | merge planes (-1.44 Mc); the cart itself is cheap | supplex_fs2.zig:329 |
| 6 | union_l16 | 2.53 (1.27 + 1.26), 2 overscan planes | 24.2 ms | merge planes (-0.72 Mc); chrome_draw.mixRgb 0.65 Mc (a table) | chrome_draw.zig:91 |
| 7 | fallen_angels | 2.36 (1.11 + 1.25), 3 planes | 19.2 ms | merge planes (-0.88 Mc); per-pixel setPixelValue calls 0.22 Mc | sprite_draw.zig:71 |
| 8 | swedish_newyear | 2.09 (1.31 + 0.78) | 22.2 ms (changed since) | the global HBL handler costs 280 BG passes (0.24 Mc); menu 0.34 Mc, Img.local 0.29 Mc | swedish_newyear/menu.zig:72 |
| 9 | larcociel2 | 2.07 (1.70 + 0.37) | 20.9 ms | present() rewrites 0.93 Mc of unchanged bytes: only modify what changes | larcociel2.zig:188 |
| 10 | tcb_colorshock | 2.05 (0.79 + 1.26), 2 overscan planes | 33.1 ms | merge planes (-0.72 Mc); panHbl 0.56 Mc in the HBL (the board measured 0.89 Mc of handlers) | tcb_colorshock.zig:127 |
| 11 | union_reps | 2.07 (1.46 + 0.61) | 21.0 ms | effects.blit 0.65 Mc; drawUnionRows rewrites 0.46 Mc unchanged | union_reps/layers.zig:149 |
| 12 | cuddly_starwars | 2.03 (1.66 + 0.37) | 23.3 ms | cart hot loop 0.98 Mc | cuddly_starwars.zig:417 |
| 13 | union_deltaforce | 1.96 (1.59 + 0.37) | 39.3 ms | band 0.60 Mc + effects.blit 0.47 Mc (the board is 2x slower than predicted: profile there) | union_deltaforce/band.zig:67 |
| 14 | lockbuster3 | 2.12 (1.58 + 0.54) | not measured | byte stores 0.88 Mc, 0.81 Mc of them rewriting unchanged bytes | lockbuster3/app.zig:445 |

Not a target: polkadots_f32 (2.21 Mc, 30.7 ms): an intentional `_f32` FPU twin (CLAUDE.md, float math).

## Predicted slow but 60 fps on the 10-20 board: verify first

skystrike 2.39 (40 s window; zig_hall.zig:61 rewrites 0.98 Mc unchanged), noextra 2.30 (noextra.zig:404, 0.90 Mc),
tlb_spoon 2.24 (tlb_spoon.zig:671 0.94 Mc, wrapQ16 divides 0.37), rno_sodium 1.99 (st.zig:118; curtain.zig:58 byte
stores), leonard 1.96 (3 planes), union_superscroller 1.90 (1,571 misaligned accesses a frame, spanfont), gen4_3615
1.72 (f64 in fate.zig:97/132), mpp_truecolor 3.26 (model over-price, see above).

## Slow on the 10-20 board but predicted 60 fps now

replicants 1.52 Mc vs 33.1 ms (its 840 passes cost the board 1.69 Mc: the model's worst FRESCO miss), big_demo
1.63 (18.1 ms) and polkadots 1.61 (18.6 ms) at the knee, mandelbrot 0.55 (22.9 ms: it finishes its picture in the
node window, not on the board at 12 s).

## Changed since the 10-20 board table (re-measure on the board)

25 carts differ from the a9a032eb shelf. New: gnomes 0.66, hmdfac 0.69, replicants_arkanoid2 0.74 Mc (all 60 fps).
Rebuilt, predicted 60 fps now and slow on 10-20: ancool 0.81 (was 25.0 ms), bladerunners 0.78 (22.0), chonchon
0.91 (43.8), dbug 0.88 (35.0), grodan_kvack 0.64 (34.8), larcociel5 0.99 (28.7), lockbuster2 0.87 (29.4), stcs
1.04 (20.7). Rebuilt and still slow: union_main 3.25, union_intro 3.25, swedish_newyear 2.09. Rebuilt, 60 fps
both: audio, chonchon2, ikplus, mentalhangover, replicants_emlyn(_f32), scrolllab, snyd_90, sysinfo, ulm_dsots,
union_textracker.

## Every cart predicted under 60 fps (generated)

| # | cart | budget Mc (cart + FRESCO) | ~fps | planes | costliest plane (Mc) | lever | next | frame_cost est Mc | board 10-20 | since 10-20 | window |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | mpp_truecolor | 3.26 (1.57 + 1.69) | 30.7 | 4 | p1 normal+HBL 0.44 | cart hot spot cart:f15 loop@0x7bc (1.44 Mc, integer) | merge planes (4 -> 1 saves ~1.32 Mc of FRESCO) | 4.05 | 16.5 ms |  | 40 s |
| 2 | union_main | 3.25 (1.27 + 1.98) | 30.8 | 3 | p1 overscan+HBL 0.72 | merge planes (3 -> 1 saves ~1.44 Mc of FRESCO) | CHISEL wait (250 blits/frame, 0.84 Mc) | 3.16 | 34.1 ms | changed | 12 s |
| 3 | union_intro | 3.25 (1.27 + 1.98) | 30.7 | 3 | p1 overscan+HBL 0.72 | merge planes (3 -> 1 saves ~1.44 Mc of FRESCO) | CHISEL wait (254 blits/frame, 0.84 Mc) | 3.16 | 19.7 ms | changed | 40 s |
| 4 | stniccc | 3.09 (2.55 + 0.54) | 32.4 | 1 | p0 overscan+HBL 0.54 | CHISEL wait (1649 blits/frame, 1.71 Mc) | only modify what changes (~1.278 Mc of redundant stores) | 3.25 | 22.1 ms |  | 40 s |
| 5 | phenomena | 2.82 (2.28 + 0.54) | 35.4 | 1 | p0 overscan+HBL 0.54 | only modify what changes (~1.032 Mc of redundant stores) | cart hot spot cart:f79 loop@0x2870 (0.89 Mc, bus: narrow stores) | 2.99 | - |  | 40 s |
| 6 | music | 2.7 (2.16 + 0.54) | 37 | 1 | p0 overscan+HBL 0.54 | cart hot spot cart:f59 loop@0x28dc (0.68 Mc, integer) | only modify what changes (~0.267 Mc of redundant stores) | 2.86 | 25.4 ms |  | 12 s |
| 7 | supplex_fs2 | 2.58 (0.6 + 1.98) | 38.8 | 3 | p1 overscan+HBL 0.72 | merge planes (3 -> 1 saves ~1.44 Mc of FRESCO) | only modify what changes (~0.161 Mc of redundant stores) | 2.49 | 33.2 ms |  | 12 s |
| 8 | union_l16 | 2.53 (1.27 + 1.26) | 39.6 | 2 | p1 overscan+HBL 0.72 | merge planes (2 -> 1 saves ~0.72 Mc of FRESCO) | cart hot spot cart:f79 loop@0x42f5 (0.36 Mc, integer) | 2.57 | 24.2 ms |  | 40 s |
| 9 | skystrike | 2.39 (1.85 + 0.54) | 41.8 | 1 | p2 overscan+HBL 0.54 | only modify what changes (~1.765 Mc of redundant stores) | cart hot spot cart:f295 loop@0x18909 (0.98 Mc, integer) | 2.56 | 16.5 ms |  | 40 s |
| 10 | fallen_angels | 2.36 (1.11 + 1.25) | 42.5 | 3 | p1 normal 0.44 | merge planes (3 -> 1 saves ~0.88 Mc of FRESCO) | cart hot spot cart:f69 (0.22 Mc, integer) | 3 | 19.2 ms |  | 40 s |
| 11 | noextra | 2.3 (1.76 + 0.54) | 43.5 | 1 | p0 overscan+HBL 0.54 | cart hot spot cart:f50 loop@0x1be7 (0.9 Mc, integer) | CHISEL wait (6 blits/frame, 0.17 Mc) | 2.46 | 16.5 ms |  | 40 s |
| 12 | tlb_spoon | 2.24 (1.87 + 0.37) | 44.7 | 1 | p0 normal 0.37 | cart hot spot cart:f45 loop@0x245c (0.94 Mc, integer) | only modify what changes (~0.189 Mc of redundant stores) | 2.57 | 16.5 ms |  | 40 s |
| 13 | polkadots_f32 | 2.21 (1.84 + 0.37) | 45.2 | 1 | p0 normal 0.37 | CHISEL wait (227 blits/frame, 0.33 Mc) | only modify what changes (~0.261 Mc of redundant stores) | 2.55 | 30.7 ms |  | 12 s |
| 14 | lockbuster3 | 2.12 (1.58 + 0.54) | 47.1 | 1 | p0 overscan+HBL 0.54 | only modify what changes (~0.996 Mc of redundant stores) | cart hot spot cart:f56 loop@0x22fc (0.88 Mc, bus: narrow stores) | 2.29 | - |  | 40 s |
| 15 | swedish_newyear | 2.09 (1.31 + 0.78) | 47.8 | 1 | p0 overscan+HBL 0.54 | cart hot spot cart:f82 loop@0xdbdf (0.34 Mc, integer) | only modify what changes (~0.283 Mc of redundant stores) | 2.01 | 22.2 ms | changed | 40 s |
| 16 | larcociel2 | 2.07 (1.7 + 0.37) | 48.3 | 1 | p0 normal+HBL 0.37 | only modify what changes (~1.362 Mc of redundant stores) | cart hot spot cart:f28 loop@0xcec (1.01 Mc, integer) | 2.4 | 20.9 ms |  | 12 s |
| 17 | union_reps | 2.07 (1.46 + 0.61) | 48.3 | 1 | p0 normal+HBL 0.37 | cart hot spot cart:f76 loop@0x4fa1 (0.65 Mc, integer) | only modify what changes (~0.467 Mc of redundant stores) | 2.16 | 21.0 ms |  | 40 s |
| 18 | tcb_colorshock | 2.05 (0.79 + 1.26) | 48.7 | 2 | p1 overscan+HBL 0.72 | merge planes (2 -> 1 saves ~0.72 Mc of FRESCO) | cart hot spot cart:f17 loop@0xc7c (0.56 Mc, integer) | 2.09 | 33.1 ms |  | 12 s |
| 19 | cuddly_starwars | 2.03 (1.66 + 0.37) | 49.3 | 1 | p0 normal+HBL 0.37 | cart hot spot cart:f42 loop@0x24bd (0.98 Mc, integer) | CHISEL wait (26 blits/frame, 0.15 Mc) | 2.36 | 23.3 ms |  | 40 s |
| 20 | rno_sodium | 1.99 (1.62 + 0.37) | 50.3 | 1 | p0 normal 0.37 | only modify what changes (~1.067 Mc of redundant stores) | cart hot spot cart:f41 loop@0x182a (0.59 Mc, integer) | 2.32 | 16.5 ms |  | 12 s |
| 21 | leonard | 1.96 (0.71 + 1.25) | 51 | 3 | p1 normal 0.44 | merge planes (3 -> 1 saves ~0.88 Mc of FRESCO) | CHISEL wait (314 blits/frame, 0.51 Mc) | 2.6 | 16.8 ms |  | 12 s |
| 22 | union_deltaforce | 1.96 (1.59 + 0.37) | 50.9 | 1 | p0 normal 0.37 | cart hot spot cart:f65 loop@0x435e (0.6 Mc, integer) | CHISEL wait (65 blits/frame, 0.11 Mc) | 2.3 | 39.3 ms |  | 12 s |
| 23 | union_superscroller | 1.9 (1.53 + 0.37) | 52.7 | 1 | p0 normal+HBL 0.37 | misaligned accesses (1571/frame, ~0.33 Mc) | only modify what changes (~0.32 Mc of redundant stores) | 2.23 | 16.6 ms |  | 40 s |
| 24 | gen4_3615 | 1.72 (1.18 + 0.54) | 58.3 | 1 | p0 overscan+HBL 0.54 | CHISEL wait (105 blits/frame, 0.28 Mc) | cart hot spot cart:f50 loop@0x2e69 (0.22 Mc, f64) | 1.88 | 16.5 ms |  | 40 s |

SLOW 24 of 108; in the knee band 1.67-2.1: 10

AT 60 (budget <= 1.67 Mc): big_demo 1.63, polkadots 1.61, bubblebobble 1.59, ulm_spoon_distorter 1.54, replicants 1.52, naos_nitrowave 1.5, dyno_paradis3 1.49, deltaforce2 1.44, vex 1.39, mentalhangover 1.38, union_demo 1.36, automation442 1.34, union_intro_screen 1.27, tsl_hybridglenz 1.27, rno_natrium 1.25, union_tnt3 1.12, rick_dangerous 1.1, snyd_90 1.06, fuji_hobbytronic 1.05, stcs_css3 1.05, stcs 1.04, joust 1.02, replicants_garfield 1.02, dune_gen4 1.01, larcociel5 0.99, deltaforce 0.97, gem 0.97, ikplus 0.96, replicants_emlyn_f32 0.96, medium_overscan 0.94, tcb_spreadpoint 0.93, maxi 0.93, elite_snooker 0.92, chonchon 0.91, ics 0.9, tcb_weirddream 0.89, replicants_emlyn 0.89, union_multifake 0.88, replicants_kickoff2 0.88, dbug 0.88, tex_neoshow 0.87, lockbuster2 0.87, replicants_dd2 0.84, elite_cfsr 0.82, dhs_0pxl0reg 0.82, ancool 0.81, rust-v8_populous 0.8, bladerunners 0.78, union_texcopier 0.76, replicants_arkanoid2 0.74, union_tnt1 0.74, blitter 0.72, chonchon2 0.72, c-fujiboink 0.71, empire 0.71, hmdfac 0.69, st_replay 0.68, obj 0.67, equinox 0.67, union_tnt2 0.66, gnomes 0.66, grodan_kvack 0.64, tex 0.63, c-screen34 0.62, scrolllab 0.58, trsi_transarctica 0.58, ulm_dsots 0.57, badflicker 0.56, fullscreen 0.55, mandelbrot 0.55, res_switch 0.55, sysinfo 0.55, tutorial 0.53, shapes 0.52, sap_test 0.49, stream 0.42, union_textracker 0.39, kickoff2 0.37, north_south 0.37, raytrace 0.37, raytrace_f32 0.37, scroll 0.37, union_beatdis 0.37, xm_test 0.37
