# LUT diet of the 7010: where the LUTs go, and what a diet that keeps every feature can free

Study, 10-11 Nov 2026, branch `study/lut-diet` (on `feat/desk-border-colour` bbaf4eb3 + `study/ziggy-big-reads`
acfac8cf). Matt: "find miracles". Skeleton: filled as the measurements come in (prototypes/lut_diet/).

## Reference: the desk-border build (9 Nov, fit_timing)

Synth 16,958 LUT (96.35 %), 15,884 FF; after opt/place/route 15,716 LUT (89.30 %), 15,953 FF,
slices 4,400/4,400, BRAM 54.5/60 tiles, DSP 72/80, 730 control sets. Closed only by a re-route
(NoTimingRelaxation + phys_opt AggressiveExplore), sys WNS +0.038 ns.
