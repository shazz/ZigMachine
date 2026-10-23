# Frame budget, 2026-10-23 (feat/frame-budget)

`node apps/frame_cost.mjs <cart.wasm> --budget` prints what a cart may spend once FRESCO has had its share:

```
union_main: cart 1.27 Mc of 0 allowed with 3 planes -> ~30.8 fps (cart 1.27 + FRESCO 1.98 = 3.25 Mc of a 1.67 Mc frame; ESTIMATE)
  plane 0 overscan    280 passes   0.54 Mc  HBL handler, 280 calls
  plane 1 overscan    280 passes   0.72 Mc  HBL handler, 280 calls  <- costliest
  plane 2 overscan    280 passes   0.72 Mc  HBL handler, 280 calls
  passes are every line new: the board's dirty-line planner can skip unchanged ones
```

(union_main of the 2026-10-20 shelf; the board measured cart 1.32 + FRESCO 1.98 Mc, 34 ms.)

Data: the board fps table of 2026-10-20 (prototypes/chisel_queue_re/arms/base/, the probe's `cart_c`, `comp_busy`,
`passes`, `hbl` columns), every cart estimated from the a9a032eb shelf (`--warmup 720 --frames 300`), the same 71
fitted carts as the cost-model recalibration (rebuilt carts excluded).

## The serial model holds on the board

The sequencer runs after `cart.frame()` and the CPU waits for it, so a frame is the cart's cycles PLUS the
compositor's. With the board's MEASURED parts, `cart_c + comp_busy x 0.8 + hbl <= 1.67 Mc` puts **70 of the 71**
fitted carts (101 of all 103) on the right side of 60 fps; `frame_c = cart_c + seq_c` within 0.9 % on every cart.

## FRESCO by line pass

`vseq.c` issues one layer of 280 passes per enabled plane (every raster line, the handler on the lines the plane
covers) and, when a global handler stops the clear being one CLEAR, 280 BG passes. A pass costs by the plane's
row width and by whether its layer is the frame's first (it paints over the clear) or a later one (it mixes):

| pass | sys cycles (fitted, least squares on comp_busy) |
|---|---|
| narrow (320) plane, first layer | 1327 |
| narrow plane, later layer | 1578 |
| wide (400: overscan / fullscreen / medium), first layer | 1911 |
| wide plane, later layer | 2583 |
| BG pass (global handler) | 868 |

FRESCO against the board's `comp_busy`: **median 1 %, p90 26 %** (one cost per pass, no width/layer split: 21 %).
The model's passes equal the board's on 57 of 71 carts; the rest are lines the dirty-line planner skipped (a
normal plane's 80 border lines when its planner is on: 200 passes), which the model does not predict: its passes
are every line new, an upper bound.

## Totals

| | frame_cost total (cart + 0.11 + 0.59 x planes) | budget (cart + FRESCO passes) |
|---|---|---|
| against the board's measured sum, 71 carts | median 28 %, p90 89 % | **median 12 %, p90 43 %** |
| board frame time, 13 carts under 60 fps | median 20 %, p90 53 %, max 58 % | median 27 %, p90 39 %, max 99 % |
| right side of 60 fps | 63 / 71 | 63 / 71 |

The budget is the better decomposition (its FRESCO part is right to 1 %, and its total tracks what the board
measures twice as closely); against average frame time near the knee neither wins, because frame time
quantizes to whole VBLs (PERF_AUDIT "The knee is a band") and what is left is the cart side's own error (~18 %
median against `cart_c`). The worst budget misses are cart-side: mandelbrot (0.01 Mc estimated: it finishes
its picture in the node window) and replicants (its comp is 1.69 Mc on the board for 840 passes, more than the
fit gives three narrow planes).

## Per cart

| cart | board ms | board FRESCO Mc | budget FRESCO Mc | passes board / model | budget Mc (cart + FRESCO) | frame_cost Mc |
|---|---|---|---|---|---|---|
| supplex_fs2 | 33.2 | 1.98 | 1.98 | 840 / 840 | 2.58 (0.6 + 1.98) | 2.49 |
| replicants | 33.1 | 1.69 | 1.26 | 840 / 840 | 1.53 (0.27 + 1.26) | 2.16 |
| tcb_colorshock | 33.1 | 1.26 | 1.26 | 560 / 560 | 2.05 (0.79 + 1.26) | 2.09 |
| polkadots_f32 | 30.7 | 0.37 | 0.37 | 280 / 280 | 2.21 (1.84 + 0.37) | 2.55 |
| music | 25.4 | 0.56 | 0.54 | 280 / 280 | 2.70 (2.16 + 0.54) | 2.86 |
| ancool | 25 | 1.30 | 1.26 | 840 / 840 | 1.98 (0.72 + 1.26) | 2.62 |
| cuddly_starwars | 23.3 | 0.38 | 0.37 | 200 / 280 | 2.02 (1.65 + 0.37) | 2.36 |
| mandelbrot | 22.9 | 0.55 | 0.54 | 280 / 280 | 0.55 (0.01 + 0.54) | 0.72 |
| swedish_newyear | 22.2 | 0.79 | 0.78 | 560 / 560 | 2.01 (1.23 + 0.78) | 1.94 |
| stniccc | 22.1 | 0.37 | 0.37 | 280 / 280 | 1.03 (0.66 + 0.37) | 1.37 |
| fallen_angels | 19.2 | 1.22 | 1.26 | 840 / 840 | 2.36 (1.1 + 1.26) | 2.99 |
| polkadots | 18.6 | 0.37 | 0.37 | 280 / 280 | 1.61 (1.24 + 0.37) | 1.94 |
| big_demo | 18.1 | 0.56 | 0.54 | 280 / 280 | 1.63 (1.09 + 0.54) | 1.8 |
| leonard | 16.8 | 0.69 | 1.26 | 840 / 840 | 1.97 (0.71 + 1.26) | 2.6 |
| raytrace | 16.8 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| tcb_weirddream | 16.7 | 0.37 | 0.37 | 280 / 280 | 0.89 (0.52 + 0.37) | 1.22 |
| c-fujiboink | 16.7 | 0.38 | 0.37 | 200 / 280 | 0.71 (0.34 + 0.37) | 1.04 |
| deltaforce2 | 16.6 | 0.89 | 0.81 | 400 / 560 | 1.44 (0.63 + 0.81) | 1.93 |
| bubblebobble | 16.6 | 0.55 | 0.54 | 280 / 280 | 1.59 (1.05 + 0.54) | 1.75 |
| replicants_dd2 | 16.6 | 0.37 | 0.37 | 280 / 280 | 0.84 (0.47 + 0.37) | 1.17 |
| rust-v8_populous | 16.6 | 0.37 | 0.37 | 280 / 280 | 0.79 (0.42 + 0.37) | 1.13 |
| replicants_garfield | 16.6 | 0.62 | 0.61 | 480 / 560 | 1.02 (0.41 + 0.61) | 1.11 |
| stcs_css3 | 16.6 | 0.62 | 0.61 | 480 / 560 | 0.98 (0.37 + 0.61) | 1.07 |
| replicants_kickoff2 | 16.6 | 0.56 | 0.54 | 280 / 280 | 0.88 (0.34 + 0.54) | 1.04 |
| elite_cfsr | 16.6 | 0.55 | 0.54 | 280 / 280 | 0.82 (0.28 + 0.54) | 0.98 |
| tex | 16.6 | 0.37 | 0.37 | 280 / 280 | 0.63 (0.26 + 0.37) | 0.96 |
| st_replay | 16.6 | 0.37 | 0.54 | 280 / 280 | 0.68 (0.14 + 0.54) | 0.85 |
| sap_test | 16.6 | 0.38 | 0.37 | 200 / 280 | 0.49 (0.12 + 0.37) | 0.82 |
| raytrace_f32 | 16.6 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| mpp_truecolor | 16.5 | 0.38 | 0.64 | 200 / 451 | 2.14 (1.5 + 0.64) | 2.57 |
| rno_sodium | 16.5 | 0.37 | 0.37 | 280 / 280 | 1.99 (1.62 + 0.37) | 2.32 |
| naos_nitrowave | 16.5 | 0.56 | 0.54 | 280 / 280 | 1.50 (0.96 + 0.54) | 1.67 |
| noextra | 16.5 | 0.55 | 0.54 | 280 / 280 | 1.46 (0.92 + 0.54) | 1.62 |
| rno_natrium | 16.5 | 0.37 | 0.37 | 280 / 280 | 1.22 (0.85 + 0.37) | 1.56 |
| ulm_spoon_distorter | 16.5 | 0.55 | 0.54 | 280 / 280 | 1.33 (0.79 + 0.54) | 1.5 |
| deltaforce | 16.5 | 1.14 | 0.81 | 560 / 560 | 0.97 (0.16 + 0.81) | 1.46 |
| rick_dangerous | 16.5 | 0.37 | 0.37 | 280 / 280 | 1.09 (0.72 + 0.37) | 1.42 |
| skystrike | 16.5 | 0.56 | 0.54 | 280 / 280 | 1.23 (0.69 + 0.54) | 1.4 |
| fuji_hobbytronic | 16.5 | 0.38 | 0.37 | 200 / 280 | 1.05 (0.68 + 0.37) | 1.39 |
| automation442 | 16.5 | 1.27 | 1.26 | 560 / 560 | 1.34 (0.08 + 1.26) | 1.38 |
| gen4_3615 | 16.5 | 0.56 | 0.54 | 280 / 280 | 1.18 (0.64 + 0.54) | 1.34 |
| gem | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.97 (0.6 + 0.37) | 1.3 |
| tcb_spreadpoint | 16.5 | 0.38 | 0.37 | 200 / 280 | 0.93 (0.56 + 0.37) | 1.26 |
| elite_snooker | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.92 (0.55 + 0.37) | 1.25 |
| dyno_paradis3 | 16.5 | 0.55 | 0.54 | 280 / 280 | 1.05 (0.51 + 0.54) | 1.22 |
| ics | 16.5 | 0.38 | 0.37 | 200 / 280 | 0.89 (0.52 + 0.37) | 1.22 |
| dune_gen4 | 16.5 | 0.56 | 0.54 | 280 / 280 | 0.99 (0.45 + 0.54) | 1.16 |
| medium_overscan | 16.5 | 0.53 | 0.54 | 280 / 280 | 0.94 (0.4 + 0.54) | 1.11 |
| maxi | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.92 (0.38 + 0.54) | 1.09 |
| tsl_hybridglenz | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.92 (0.38 + 0.54) | 1.08 |
| blitter | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.72 (0.35 + 0.37) | 1.05 |
| empire | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.71 (0.34 + 0.37) | 1.04 |
| tex_neoshow | 16.5 | 0.56 | 0.54 | 280 / 280 | 0.87 (0.33 + 0.54) | 1.03 |
| obj | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.66 (0.29 + 0.37) | 1 |
| tlb_spoon | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.55 (0.18 + 0.37) | 0.89 |
| shapes | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.52 (0.15 + 0.37) | 0.86 |
| tutorial | 16.5 | 0.38 | 0.37 | 200 / 280 | 0.53 (0.16 + 0.37) | 0.86 |
| equinox | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.66 (0.12 + 0.54) | 0.83 |
| joust | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.46 (0.09 + 0.37) | 0.79 |
| c-screen34 | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.62 (0.08 + 0.54) | 0.78 |
| stream | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.42 (0.05 + 0.37) | 0.75 |
| trsi_transarctica | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.57 (0.03 + 0.54) | 0.74 |
| vex | 16.5 | 0.62 | 0.78 | 480 / 560 | 0.81 (0.03 + 0.78) | 0.74 |
| badflicker | 16.5 | 0.56 | 0.54 | 280 / 280 | 0.56 (0.02 + 0.54) | 0.72 |
| fullscreen | 16.5 | 0.55 | 0.54 | 280 / 280 | 0.55 (0.01 + 0.54) | 0.72 |
| res_switch | 16.5 | 0.42 | 0.54 | 200 / 280 | 0.55 (0.01 + 0.54) | 0.71 |
| kickoff2 | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| north_south | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| scroll | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| xm_test | 16.5 | 0.37 | 0.37 | 280 / 280 | 0.37 (0 + 0.37) | 0.7 |
| dhs_0pxl0reg | 16.5 | 0.39 | 0.24 | 423 / 280 | 0.81 (0.57 + 0.24) | 0.68 |
