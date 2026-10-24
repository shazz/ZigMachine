# Shelf frame budget, 2026-10-24

All 108 carts with a disk on origin/main ca9aa4bf (FRESCO 3a, ~25 optimized carts since yesterday) through
`node apps/frame_cost.mjs --budget`, in two windows (frames 721-1020, the board table's 12 s; 2401-2700, 40 s), the
worse one ranked; names from `tools/perf_names.sh`. Yesterday: fpga/review/reports/shelf_budget_2026-10-23.md.

**8 of 108 are predicted under 60 fps (24 yesterday), 3 in the 1.67-2.1 knee band.** Board tonight (card main
f33ce327): replicants, automation442, supplex_fs2, tcb_colorshock, union_l16, fallen_angels 60.4 fps; union_intro's main
59.2; union_deltaforce 52.9 (predicted 1.28 Mc: a model miss, profile it on the board).

## Taken (one optimizer each)

| cart | budget Mc | why this one | lever |
|---|---|---|---|
| noextra | 2.30 (1.76 + 0.54) | slow in the 40 s window (the board table measured 12 s) | demo_main.frame at noextra.zig:404, 0.90 Mc |
| tlb_spoon | 2.25 (1.88 + 0.37) | the same | demo_main.frame at tlb_spoon.zig:671, 0.94 Mc; redundant stores |
| leonard | 1.96 (0.71 + 1.25) | 16.8 ms on the 10-20 board at 12 s: really just under 60 | 3 planes -> merge (~0.88 Mc); 314 CHISEL blits (0.51 Mc) |
| mpp_truecolor | 3.26 (1.57 + 1.69) | the costliest; 60 fps on the board at 12 s, so check its 40 s phase first | its HBL (mpp_truecolor.zig:88) 1.44 Mc; 4 planes (the board's planner composed 200 passes: the model's FRESCO over-prices it) |

## Not taken

- union_intro 2.13 (2 overscan planes, 132 blits): its main screen lives in scenes/union/, owned by the union agent.
- rno_sodium 1.99: predicted slow in the SAME 12 s window the board measured at 60 fps: a model over-price.
- gen4_3615 1.72: its float-free version (perf/opt-gen4, 1.29 Mc) is landing.
- polkadots_f32 2.30: an intentional FPU twin.
- Excluded by the lead: bubblebobble, kickoff2, gnomes, hmdfac (ports revisited whole), tcb_colorshock (open board race;
  1.43 Mc now), leonard_spirit and hippel_musicdisk (running agents).

## Every cart predicted under 60 fps (generated)

| # | cart | budget Mc (cart + FRESCO) | yesterday | ~fps | planes | costliest plane | lever | next | board | excluded | window |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | mpp_truecolor | 3.26 (1.57 + 1.69) | 3.26 | 30.7 | 4 | p1 normal+HBL 0.44 | hot scenes.mpp_truecolor.hbl [apps/zig/scenes/mpp_truecolor.zig:88] 1.44 Mc (integer) | merge planes (4 -> 1 saves ~1.32 Mc) | 16.5 ms (10-20) |  | 40 s |
| 2 | polkadots_f32 | 2.3 (1.93 + 0.37) | 2.21 | 43.4 | 1 | p0 normal 0.37 | CHISEL wait 227 blits (0.33 Mc) | hot demo_main.frame [apps/zig/scenes/polkadots/shade_f32.zig:105] 0.32 Mc (integer) | 30.7 ms (10-20) | intentional FPU twin | 12 s |
| 3 | noextra | 2.3 (1.76 + 0.54) | 2.3 | 43.5 | 1 | p0 overscan+HBL 0.54 | hot demo_main.frame [apps/zig/scenes/noextra.zig:404] 0.9 Mc (integer) | CHISEL wait 6 blits (0.17 Mc) | 16.5 ms (10-20) |  | 40 s |
| 4 | tlb_spoon | 2.25 (1.88 + 0.37) | 2.24 | 44.5 | 1 | p0 normal 0.37 | hot demo_main.frame [apps/zig/scenes/tlb_spoon.zig:671] 0.94 Mc (integer) | redundant stores ~0.189 Mc | 16.5 ms (10-20) |  | 40 s |
| 5 | union_intro | 2.13 (0.87 + 1.26) | 3.25 | 47 | 2 | p1 overscan+HBL 0.72 | merge planes (2 -> 1 saves ~0.72 Mc) | CHISEL wait 132 blits (0.44 Mc) | 16.9 ms tonight |  | 40 s |
| 6 | rno_sodium | 1.99 (1.62 + 0.37) | 1.99 | 50.3 | 1 | p0 normal 0.37 | redundant stores ~1.067 Mc | hot demo_main.frame [apps/zig/scenes/rno_sodium/st.zig:118] 0.59 Mc (integer) | 16.5 ms (10-20) |  | 12 s |
| 7 | leonard | 1.96 (0.71 + 1.25) | 1.96 | 51 | 3 | p1 normal 0.44 | merge planes (3 -> 1 saves ~0.88 Mc) | CHISEL wait 314 blits (0.51 Mc) | 16.8 ms (10-20) |  | 12 s |
| 8 | gen4_3615 | 1.72 (1.18 + 0.54) | 1.72 | 58.3 | 1 | p0 overscan+HBL 0.54 | CHISEL wait 105 blits (0.28 Mc) | hot demo_main.frame [apps/zig/scenes/gen4_3615/fate.zig:97] 0.22 Mc (f64) | 16.5 ms (10-20) |  | 40 s |

SLOW 8 of 108; knee band 1.67-2.1: 3; not excluded: 7

AT 60 (<= 1.67 Mc): big_demo 1.63, polkadots 1.61, music 1.6 (was 2.7), bubblebobble 1.59, ulm_spoon_distorter 1.54, replicants 1.52, naos_nitrowave 1.5, cuddly_starwars 1.49 (was 2.03), dyno_paradis3 1.49, deltaforce2 1.44, tcb_colorshock 1.43 (was 2.05), vex 1.39, mentalhangover 1.38, automation442 1.34, union_demo 1.3, union_deltaforce 1.28 (was 1.96), tsl_hybridglenz 1.27, rno_natrium 1.25, swedish_newyear 1.25 (was 2.09), anima 1.24, skystrike 1.23 (was 2.39), leonard_spirit 1.18, union_superscroller 1.17 (was 1.9), union_tnt3 1.13, supplex_fs2 1.11 (was 2.58), rick_dangerous 1.1, stniccc 1.1 (was 3.09), snyd_90 1.07, union_l16 1.06 (was 2.53), fuji_hobbytronic 1.05, union_reps 1.05 (was 2.07), stcs_css3 1.05, stcs 1.04, phenomena 1.04 (was 2.82), fallen_angels 1.02 (was 2.36), joust 1.02, replicants_garfield 1.02, dune_gen4 1.01, larcociel5 0.99, replicants_emlyn_f32 0.99, deltaforce 0.97, gem 0.97, ikplus 0.96, medium_overscan 0.94, tcb_spreadpoint 0.93, lockbuster3 0.93 (was 2.12), maxi 0.93, elite_snooker 0.92, chonchon 0.91, ics 0.9, tcb_weirddream 0.89, replicants_emlyn 0.89, union_multifake 0.88, replicants_kickoff2 0.88, dbug 0.88, tex_neoshow 0.87, lockbuster2 0.87, replicants_dd2 0.84, elite_cfsr 0.82, dhs_0pxl0reg 0.82, ancool 0.81, rust-v8_populous 0.8, bladerunners 0.78, union_texcopier 0.76, replicants_arkanoid2 0.74, union_tnt1 0.74, larcociel2 0.73 (was 2.07), blitter 0.72, chonchon2 0.72, c-fujiboink 0.71, empire 0.71, hmdfac 0.69, st_replay 0.68, obj 0.67, equinox 0.67, union_tnt2 0.66, gnomes 0.66, grodan_kvack 0.64, tex 0.63, c-screen34 0.62, scrolllab 0.58, trsi_transarctica 0.58, ulm_dsots 0.57, badflicker 0.56, fullscreen 0.55, mandelbrot 0.55, res_switch 0.55, sysinfo 0.55, tutorial 0.53, shapes 0.52, sap_test 0.49, stream 0.42, union_textracker 0.39, kickoff2 0.37, north_south 0.37, raytrace 0.37, raytrace_f32 0.37, scroll 0.37, union_beatdis 0.37, xm_test 0.37
