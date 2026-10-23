# Cost model recalibration, 2026-10-23 (feat/cost-model-recal)

apps/perf/cost_model.mjs refitted to the POSTED-STORE board: board fps + the native bench cart from the same
session (prototypes/chisel_queue_re/arms/base/, 2026-10-20: main firmware + bitstream, W64, posted stores,
FPU), every cart estimated from the a9a032eb shelf (`--warmup 720 --frames 300`, unattended).
Method and constants: docs/PERF_AUDIT.md "Fitted to the board (2026-10-23)".

Excluded from the fit (rebuilt since a9a032eb, or under a running optimizer): stcs, dbug, lockbuster2,
mentalhangover, grodan_kvack, ikplus, chonchon*, larcociel*, union_*, audio, replicants_emlyn(_f32),
scrolllab, sysinfo, ulm_dsots, bladerunners, phenomena, snyd_90. Listed below, marked.

## Headline

| | old model | new model |
|---|---|---|
| frame time, 13 carts under 60 fps | median 38 %, p90 108 %, max 185 % | median 20 %, p90 53 %, max 58 % |
| frame time, all 71 fitted carts | median 1 %, p90 70 %, max 705 % | median 0 %, p90 33 %, max 58 % |
| cart cycles vs board `cart_c`, 56 carts > 0.1 Mc | median 33 %, p90 366 % | median 18 %, p90 106 % |
| 60 fps knee (best split, est. Mc/frame) | 2.82 (7 of 71 misclassified) | **1.75** (6 of 71) |
| est. Mc of 60 fps carts: p90 / max | 2.49 / 13.36 | 1.62 / 2.60 |

A 60 fps cart only bounds its frame at <= 16.6 ms, so it counts as an error only when predicted slower.
Error = predicted / board frame time (x1.00 = exact).

## Frame time per cart (estimate = frame_cost mc.avg; ms = Mc x 10, floored at 16.6)

| cart | board ms | old Mc | old err | new Mc | new err | |
|---|---|---|---|---|---|---|
| chonchon | 43.8 | 6.21 | x1.42 | 5.53 | x1.26 | excluded |
| union_deltaforce | 39.3 | 3.93 | x1.00 | 2.3 | x0.59 | excluded |
| dbug | 35 | 2.94 | x0.84 | 1.67 | x0.48 | excluded |
| grodan_kvack | 34.8 | 6.26 | x1.80 | 5.25 | x1.51 | excluded |
| union_main | 34.1 | 4.48 | x1.31 | 3.16 | x0.93 | excluded |
| supplex_fs2 | 33.2 | 4.02 | x1.21 | 2.49 | x0.75 |  |
| replicants | 33.1 | 3.58 | x1.08 | 2.16 | x0.65 |  |
| tcb_colorshock | 33.1 | 9.45 | x2.85 | 2.09 | x0.63 |  |
| polkadots_f32 | 30.7 | 3.2 | x1.04 | 2.55 | x0.83 |  |
| lockbuster2 | 29.4 | 4.38 | x1.49 | 3.56 | x1.21 | excluded |
| larcociel5 | 28.7 | 8.82 | x3.07 | 4.49 | x1.56 | excluded |
| music | 25.4 | 3.18 | x1.25 | 2.86 | x1.13 |  |
| ancool | 25 | 4.18 | x1.67 | 2.62 | x1.05 |  |
| union_l16 | 24.2 | 4.36 | x1.80 | 2.56 | x1.06 | excluded |
| cuddly_starwars | 23.3 | 2.58 | x1.11 | 2.36 | x1.01 |  |
| mandelbrot | 22.9 | 1.12 | x0.72 | 0.72 | x0.72 |  |
| swedish_newyear | 22.2 | 3.24 | x1.46 | 1.94 | x0.87 |  |
| stniccc | 22.1 | 1.82 | x0.82 | 1.37 | x0.75 |  |
| bladerunners | 22 | 2.73 | x1.24 | 1.82 | x0.83 | excluded |
| union_reps | 21 | 2.35 | x1.12 | 2.14 | x1.02 | excluded |
| larcociel2 | 20.9 | 3.14 | x1.50 | 2.4 | x1.15 | excluded |
| stcs | 20.7 | 3.45 | x1.67 | 1.71 | x0.83 | excluded |
| union_intro | 19.7 | 2.33 | x1.18 | 1.7 | x0.86 | excluded |
| fallen_angels | 19.2 | 5.01 | x2.61 | 2.99 | x1.56 |  |
| polkadots | 18.6 | 2.89 | x1.55 | 1.94 | x1.04 |  |
| big_demo | 18.1 | 3.76 | x2.08 | 1.8 | x0.99 |  |
| leonard | 16.8 | 3.86 | x2.33 | 2.6 | x1.57 |  |
| raytrace | 16.8 | 1.09 | x1.00 | 0.7 | x1.00 |  |
| c-fujiboink | 16.7 | 1.43 | x1.00 | 1.04 | x1.00 |  |
| tcb_weirddream | 16.7 | 1.82 | x1.10 | 1.22 | x1.00 |  |
| bubblebobble | 16.6 | 3.69 | x2.22 | 1.75 | x1.05 |  |
| deltaforce2 | 16.6 | 2.82 | x1.70 | 1.93 | x1.16 |  |
| elite_cfsr | 16.6 | 2.04 | x1.23 | 0.98 | x1.00 |  |
| raytrace_f32 | 16.6 | 1.09 | x1.00 | 0.7 | x1.00 |  |
| replicants_garfield | 16.6 | 2.28 | x1.37 | 1.11 | x1.00 |  |
| replicants_kickoff2 | 16.6 | 1.43 | x1.00 | 1.04 | x1.00 |  |
| replicants_dd2 | 16.6 | 2.82 | x1.70 | 1.17 | x1.00 |  |
| sap_test | 16.6 | 1.19 | x1.00 | 0.82 | x1.00 |  |
| scrolllab | 16.6 | 2.94 | x1.77 | 1.43 | x1.00 | excluded |
| st_replay | 16.6 | 1.56 | x1.00 | 0.85 | x1.00 |  |
| stcs_css3 | 16.6 | 1.4 | x1.00 | 1.07 | x1.00 |  |
| union_beatdis | 16.6 | 1.09 | x1.00 | 0.7 | x1.00 | excluded |
| union_superscroller | 16.6 | 4.02 | x2.42 | 2.19 | x1.32 | excluded |
| union_multifake | 16.6 | 1.49 | x1.00 | 1.21 | x1.00 | excluded |
| tex | 16.6 | 1.34 | x1.00 | 0.96 | x1.00 |  |
| rust-v8_populous | 16.6 | 1.54 | x1.00 | 1.13 | x1.00 |  |
| automation442 | 16.5 | 2.45 | x1.48 | 1.38 | x1.00 |  |
| badflicker | 16.5 | 1.12 | x1.00 | 0.72 | x1.00 |  |
| blitter | 16.5 | 1.45 | x1.00 | 1.05 | x1.00 |  |
| union_texcopier | 16.5 | 1.24 | x1.00 | 0.85 | x1.00 | excluded |
| deltaforce | 16.5 | 2.49 | x1.50 | 1.46 | x1.00 |  |
| dhs_0pxl0reg | 16.5 | 0.6 | x1.00 | 0.68 | x1.00 |  |
| dune_gen4 | 16.5 | 2.39 | x1.44 | 1.16 | x1.00 |  |
| dyno_paradis3 | 16.5 | 1.82 | x1.10 | 1.22 | x1.00 |  |
| elite_snooker | 16.5 | 1.65 | x1.00 | 1.25 | x1.00 |  |
| empire | 16.5 | 1.57 | x1.00 | 1.04 | x1.00 |  |
| equinox | 16.5 | 1.18 | x1.00 | 0.83 | x1.00 |  |
| fuji_hobbytronic | 16.5 | 1.89 | x1.14 | 1.39 | x1.00 |  |
| fullscreen | 16.5 | 1.12 | x1.00 | 0.72 | x1.00 |  |
| gem | 16.5 | 1.63 | x1.00 | 1.3 | x1.00 |  |
| ics | 16.5 | 1.59 | x1.00 | 1.22 | x1.00 |  |
| joust | 16.5 | 1.28 | x1.00 | 0.79 | x1.00 |  |
| kickoff2 | 16.5 | 1.09 | x1.00 | 0.7 | x1.00 |  |
| c-screen34 | 16.5 | 1.38 | x1.00 | 0.78 | x1.00 |  |
| maxi | 16.5 | 1.55 | x1.00 | 1.09 | x1.00 |  |
| medium_overscan | 16.5 | 1.46 | x1.00 | 1.11 | x1.00 |  |
| mpp_truecolor | 16.5 | 13.36 | x8.05 | 2.57 | x1.55 |  |
| naos_nitrowave | 16.5 | 1.99 | x1.20 | 1.67 | x1.01 |  |
| noextra | 16.5 | 1.94 | x1.17 | 1.62 | x1.00 |  |
| north_south | 16.5 | 1.09 | x1.00 | 0.7 | x1.00 |  |
| obj | 16.5 | 1.35 | x1.00 | 1 | x1.00 |  |
| replicants_emlyn | 16.5 | 1.46 | x1.00 | 1.06 | x1.00 | excluded |
| replicants_emlyn_f32 | 16.5 | 1.51 | x1.00 | 1.12 | x1.00 | excluded |
| res_switch | 16.5 | 1.1 | x1.00 | 0.71 | x1.00 |  |
| rick_dangerous | 16.5 | 1.71 | x1.03 | 1.42 | x1.00 |  |
| rno_natrium | 16.5 | 1.86 | x1.12 | 1.56 | x1.00 |  |
| rno_sodium | 16.5 | 4.87 | x2.93 | 2.32 | x1.40 |  |
| scroll | 16.5 | 1.09 | x1.00 | 0.7 | x1.00 |  |
| shapes | 16.5 | 1.31 | x1.00 | 0.86 | x1.00 |  |
| skystrike | 16.5 | 1.97 | x1.19 | 1.4 | x1.00 |  |
| stream | 16.5 | 2.11 | x1.27 | 0.75 | x1.00 |  |
| snyd_90 | 16.5 | 1.68 | x1.01 | 0.99 | x1.00 | excluded |
| sysinfo | 16.5 | 1.1 | x1.00 | 0.71 | x1.00 | excluded |
| tcb_spreadpoint | 16.5 | 1.6 | x1.00 | 1.26 | x1.00 |  |
| union_textracker | 16.5 | 1.12 | x1.00 | 0.73 | x1.00 | excluded |
| tex_neoshow | 16.5 | 1.67 | x1.01 | 1.03 | x1.00 |  |
| gen4_3615 | 16.5 | 1.62 | x1.00 | 1.34 | x1.00 |  |
| tlb_spoon | 16.5 | 2.18 | x1.31 | 0.89 | x1.00 |  |
| union_tnt1 | 16.5 | 1.41 | x1.00 | 1.07 | x1.00 | excluded |
| union_tnt2 | 16.5 | 1.36 | x1.00 | 0.99 | x1.00 | excluded |
| union_tnt3 | 16.5 | 1.91 | x1.15 | 1.46 | x1.00 | excluded |
| trsi_transarctica | 16.5 | 1.14 | x1.00 | 0.74 | x1.00 |  |
| tsl_hybridglenz | 16.5 | 1.48 | x1.00 | 1.08 | x1.00 |  |
| tutorial | 16.5 | 1.96 | x1.18 | 0.86 | x1.00 |  |
| ulm_spoon_distorter | 16.5 | 1.6 | x1.00 | 1.5 | x1.00 |  |
| ulm_dsots | 16.5 | 1.15 | x1.00 | 0.73 | x1.00 | excluded |
| union_intro_screen | 16.5 | 2.7 | x1.63 | 1.61 | x1.00 | excluded |
| union_demo | 16.5 | 1.57 | x1.00 | 1.43 | x1.00 | excluded |
| vex | 16.5 | 1.14 | x1.00 | 0.74 | x1.00 |  |
| xm_test | 16.5 | 1.09 | x1.00 | 0.7 | x1.00 |  |

## Cart side per cart (cart + ROM + I$ + blitter + HBL, against the board probe cart_c)

| cart | board ms | board cart Mc | old cart Mc | new cart Mc | board comp Mc | passes | |
|---|---|---|---|---|---|---|---|
| chonchon | 43.8 | 3.95 | 5.12 | 4.83 | 0.38 | 200 | excluded |
| union_intro | 19.7 | 3.59 | 0.71 | 0.72 | 0.56 | 280 | excluded |
| union_deltaforce | 39.3 | 3.48 | 2.84 | 1.60 | 0.37 | 280 | excluded |
| grodan_kvack | 34.8 | 3.03 | 5.17 | 4.54 | 0.38 | 200 | excluded |
| polkadots_f32 | 30.7 | 2.45 | 2.11 | 1.84 | 0.37 | 280 |  |
| larcociel5 | 28.7 | 2.39 | 7.73 | 3.78 | 0.38 | 200 | excluded |
| dbug | 35 | 2.33 | 0.76 | 0.38 | 1.10 | 560 | excluded |
| lockbuster2 | 29.4 | 2.19 | 3.29 | 2.86 | 0.62 | 480 | excluded |
| music | 25.4 | 1.94 | 2.09 | 2.16 | 0.56 | 280 |  |
| cuddly_starwars | 23.3 | 1.90 | 1.49 | 1.65 | 0.38 | 200 |  |
| larcociel2 | 20.9 | 1.63 | 2.05 | 1.70 | 0.38 | 200 | excluded |
| stniccc | 22.1 | 1.58 | 0.73 | 0.67 | 0.37 | 280 |  |
| union_reps | 21 | 1.43 | 1.25 | 1.44 | 0.62 | 480 | excluded |
| polkadots | 18.6 | 1.41 | 1.80 | 1.24 | 0.37 | 280 |  |
| union_main | 34.1 | 1.32 | 1.21 | 1.27 | 1.98 | 840 | excluded |
| big_demo | 18.1 | 1.23 | 2.67 | 1.09 | 0.56 | 280 |  |
| swedish_newyear | 22.2 | 1.16 | 2.14 | 1.23 | 0.79 | 560 |  |
| raytrace | 16.8 | 1.16 | 0.00 | 0.00 | 0.37 | 280 |  |
| raytrace_f32 | 16.6 | 1.15 | 0.00 | 0.00 | 0.37 | 280 |  |
| union_l16 | 24.2 | 1.06 | 2.18 | 1.26 | 1.27 | 560 | excluded |
| union_superscroller | 16.6 | 1.05 | 2.93 | 1.49 | 0.38 | 200 | excluded |
| fallen_angels | 19.2 | 1.03 | 1.73 | 1.10 | 1.22 | 840 |  |
| naos_nitrowave | 16.5 | 0.98 | 0.90 | 0.96 | 0.56 | 280 |  |
| bubblebobble | 16.6 | 0.98 | 2.60 | 1.05 | 0.55 | 280 |  |
| union_intro_screen | 16.5 | 0.94 | 1.61 | 0.90 | 0.37 | 280 | excluded |
| fuji_hobbytronic | 16.5 | 0.83 | 0.80 | 0.68 | 0.38 | 200 |  |
| union_tnt3 | 16.5 | 0.82 | 0.82 | 0.75 | 0.37 | 280 | excluded |
| tcb_weirddream | 16.7 | 0.78 | 0.73 | 0.52 | 0.37 | 280 |  |
| leonard | 16.8 | 0.72 | 0.59 | 0.71 | 0.69 | 840 |  |
| replicants_dd2 | 16.6 | 0.70 | 1.73 | 0.47 | 0.37 | 280 |  |
| rno_natrium | 16.5 | 0.69 | 0.77 | 0.85 | 0.37 | 280 |  |
| gen4_3615 | 16.5 | 0.68 | 0.53 | 0.65 | 0.56 | 280 |  |
| union_demo | 16.5 | 0.67 | 0.48 | 0.73 | 0.61 | 480 | excluded |
| ulm_spoon_distorter | 16.5 | 0.66 | 0.51 | 0.80 | 0.55 | 280 |  |
| ancool | 25 | 0.65 | 0.91 | 0.73 | 1.30 | 840 |  |
| replicants_garfield | 16.6 | 0.63 | 1.19 | 0.41 | 0.62 | 480 |  |
| scrolllab | 16.6 | 0.63 | 1.85 | 0.72 | 0.33 | 249 | excluded |
| rick_dangerous | 16.5 | 0.63 | 0.62 | 0.72 | 0.37 | 280 |  |
| skystrike | 16.5 | 0.59 | 0.88 | 0.69 | 0.56 | 280 |  |
| rno_sodium | 16.5 | 0.58 | 3.78 | 1.62 | 0.37 | 280 |  |
| sysinfo | 16.5 | 0.57 | 0.01 | 0.01 | 0.37 | 280 | excluded |
| st_replay | 16.6 | 0.57 | 0.47 | 0.14 | 0.37 | 280 |  |
| gem | 16.5 | 0.57 | 0.54 | 0.60 | 0.37 | 280 |  |
| elite_snooker | 16.5 | 0.56 | 0.56 | 0.54 | 0.37 | 280 |  |
| supplex_fs2 | 33.2 | 0.55 | 0.75 | 0.60 | 1.98 | 840 |  |
| deltaforce2 | 16.6 | 0.49 | 0.64 | 0.63 | 0.89 | 400 |  |
| ics | 16.5 | 0.46 | 0.49 | 0.52 | 0.38 | 200 |  |
| dhs_0pxl0reg | 16.5 | 0.45 | 0.60 | 0.57 | 0.39 | 423 |  |
| replicants_emlyn_f32 | 16.5 | 0.44 | 0.42 | 0.42 | 0.55 | 280 | excluded |
| bladerunners | 22 | 0.43 | 0.55 | 0.52 | 1.36 | 840 | excluded |
| dyno_paradis3 | 16.5 | 0.43 | 0.73 | 0.51 | 0.55 | 280 |  |
| union_multifake | 16.6 | 0.41 | 0.40 | 0.51 | 0.37 | 280 | excluded |
| tex_neoshow | 16.5 | 0.40 | 0.58 | 0.33 | 0.56 | 280 |  |
| rust-v8_populous | 16.6 | 0.37 | 0.45 | 0.42 | 0.37 | 280 |  |
| maxi | 16.5 | 0.37 | 0.46 | 0.38 | 0.55 | 280 |  |
| union_tnt1 | 16.5 | 0.37 | 0.31 | 0.37 | 0.37 | 280 | excluded |
| medium_overscan | 16.5 | 0.34 | 0.37 | 0.40 | 0.53 | 280 |  |
| c-fujiboink | 16.7 | 0.33 | 0.34 | 0.34 | 0.38 | 200 |  |
| union_tnt2 | 16.5 | 0.31 | 0.27 | 0.29 | 0.37 | 280 | excluded |
| replicants_kickoff2 | 16.6 | 0.30 | 0.34 | 0.34 | 0.56 | 280 |  |
| empire | 16.5 | 0.30 | 0.48 | 0.34 | 0.37 | 280 |  |
| stcs_css3 | 16.6 | 0.29 | 0.31 | 0.37 | 0.62 | 480 |  |
| tex | 16.6 | 0.26 | 0.25 | 0.26 | 0.37 | 280 |  |
| tcb_colorshock | 33.1 | 0.25 | 7.26 | 0.79 | 1.26 | 560 |  |
| stcs | 20.7 | 0.25 | 1.27 | 0.41 | 1.36 | 840 | excluded |
| replicants_emlyn | 16.5 | 0.23 | 0.37 | 0.36 | 0.56 | 280 | excluded |
| obj | 16.5 | 0.23 | 0.26 | 0.30 | 0.37 | 280 |  |
| blitter | 16.5 | 0.22 | 0.35 | 0.35 | 0.37 | 280 |  |
| replicants | 33.1 | 0.22 | 0.31 | 0.26 | 1.69 | 840 |  |
| tlb_spoon | 16.5 | 0.22 | 1.09 | 0.18 | 0.37 | 280 |  |
| elite_cfsr | 16.6 | 0.20 | 0.95 | 0.28 | 0.55 | 280 |  |
| tsl_hybridglenz | 16.5 | 0.18 | 0.39 | 0.38 | 0.55 | 280 |  |
| joust | 16.5 | 0.18 | 0.19 | 0.09 | 0.37 | 280 |  |
| deltaforce | 16.5 | 0.18 | 0.32 | 0.16 | 1.14 | 560 |  |
| c-screen34 | 16.5 | 0.15 | 0.29 | 0.08 | 0.55 | 280 |  |
| automation442 | 16.5 | 0.15 | 0.27 | 0.08 | 1.27 | 560 |  |
| union_texcopier | 16.5 | 0.13 | 0.15 | 0.14 | 0.62 | 480 | excluded |
| equinox | 16.5 | 0.12 | 0.09 | 0.12 | 0.55 | 280 |  |
| tutorial | 16.5 | 0.12 | 0.87 | 0.16 | 0.38 | 200 |  |
| shapes | 16.5 | 0.11 | 0.22 | 0.15 | 0.37 | 280 |  |
| sap_test | 16.6 | 0.11 | 0.11 | 0.12 | 0.38 | 200 |  |
| stream | 16.5 | 0.07 | 1.02 | 0.05 | 0.37 | 280 |  |
| ulm_dsots | 16.5 | 0.05 | 0.06 | 0.03 | 0.55 | 280 | excluded |
| trsi_transarctica | 16.5 | 0.03 | 0.05 | 0.03 | 0.55 | 280 |  |
| union_textracker | 16.5 | 0.03 | 0.02 | 0.02 | 0.37 | 280 | excluded |
| noextra | 16.5 | 0.02 | 0.86 | 0.92 | 0.55 | 280 |  |
| kickoff2 | 16.5 | 0.00 | 0.00 | 0.00 | 0.37 | 280 |  |
| dune_gen4 | 16.5 | 0.00 | 1.30 | 0.45 | 0.56 | 280 |  |
| north_south | 16.5 | 0.00 | 0.00 | 0.00 | 0.37 | 280 |  |
| tcb_spreadpoint | 16.5 | 0.00 | 0.51 | 0.56 | 0.38 | 200 |  |
| vex | 16.5 | 0.00 | 0.05 | 0.03 | 0.62 | 480 |  |
| scroll | 16.5 | 0.00 | 0.00 | 0.00 | 0.37 | 280 |  |
| res_switch | 16.5 | 0.00 | 0.01 | 0.01 | 0.42 | 200 |  |
| mpp_truecolor | 16.5 | 0.00 | 11.60 | 1.50 | 0.38 | 200 |  |
| union_beatdis | 16.6 | 0.00 | 0.00 | 0.00 | 0.37 | 280 | excluded |
| badflicker | 16.5 | 0.00 | 0.03 | 0.02 | 0.56 | 280 |  |
| snyd_90 | 16.5 | 0.00 | 0.59 | 0.29 | 0.76 | 560 | excluded |
| xm_test | 16.5 | 0.00 | 0.00 | 0.00 | 0.37 | 280 |  |
| fullscreen | 16.5 | 0.00 | 0.03 | 0.01 | 0.55 | 280 |  |
| mandelbrot | 22.9 | 0.00 | 0.03 | 0.01 | 0.55 | 280 |  |

## VBL overrun against the estimate (2026-10-23, feat/cost-model-vbl)

The board shows a frame for whole VBLs; `missed` / (frames + missed) is the share of VBLs that
held a late frame. Fitted carts estimated >= 1.4 Mc:

| est Mc | overrun | board ms | cart |
|---|---|---|---|
| 1.4 | 0 % | 16.5 | skystrike |
| 1.42 | 0 % | 16.5 | rick_dangerous |
| 1.46 | 0 % | 16.5 | deltaforce |
| 1.5 | 0 % | 16.5 | ulm_spoon_distorter |
| 1.56 | 0 % | 16.5 | rno_natrium |
| 1.62 | 0 % | 16.5 | noextra |
| 1.67 | 0 % | 16.5 | naos_nitrowave |
| 1.75 | 0 % | 16.6 | bubblebobble |
| 1.8 | 8 % | 18.1 | big_demo |
| 1.93 | 0 % | 16.6 | deltaforce2 |
| 1.94 | 11 % | 18.6 | polkadots |
| 1.94 | 25 % | 22.2 | swedish_newyear |
| 2.09 | 50 % | 33.1 | tcb_colorshock |
| 2.16 | 50 % | 33.1 | replicants |
| 2.32 | 0 % | 16.5 | rno_sodium |
| 2.36 | 29 % | 23.3 | cuddly_starwars |
| 2.49 | 50 % | 33.2 | supplex_fs2 |
| 2.55 | 46 % | 30.7 | polkadots_f32 |
| 2.57 | 0 % | 16.5 | mpp_truecolor |
| 2.6 | 1 % | 16.8 | leonard |
| 2.62 | 34 % | 25.0 | ancool |
| 2.86 | 35 % | 25.4 | music |
| 2.99 | 14 % | 19.2 | fallen_angels |
