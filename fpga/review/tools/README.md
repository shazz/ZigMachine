# Review tools

Companion to `../SOC_REVIEW.md`. Every number quoted in the review is reproducible from these.
Vivado 2026.1 is node-locked at `/opt/vivado/2026.1` (license OK until 2027-10-09); the host has
4 physical cores, so the chain sequentialises the Vivado runs.

## `ooc_sweep.sh` — per-block OOC synth+place+route

    bash review/tools/ooc_sweep.sh <top> <period_ns> <out_dir> <file1.v> [file2.v ...]

Runs one RTL block out-of-context on `xc7z010clg400-1` with its `clk` port constrained to
`<period_ns>` (8.0 = 125 MHz, 10.0 = 100 MHz, 6.67 = 150 MHz), then opt / place
(`ExtraTimingOpt`) / route (`MoreGlobalIterations`). Writes into `<out_dir>`:
`run.tcl`, `vivado.log`, `timing_summary.rpt`, `util.rpt`, `hier.rpt`, `ooc_<top>.dcp`.

The include path is fixed to `{gen, rtl/video, rtl/blitter, rtl/audio, third_party/jt49/hdl}` —
any block that needs more must be edited here (deliberate: keep runs auditable).
The `.dcp` can be reopened (`open_checkpoint`) for path-level reports.

## `synth_full.sh` — full-SoC flow-of-record postmortem on the current tree

    bash review/tools/synth_full.sh

Regenerates the flat gateware from the CURRENT sources with

    uv run --with meson --with ninja python -m soc.zigmachine_soc --target z7 \
      --out build/review/soc        # LiteX build, log: /tmp/opencode/rev/eln.log

then runs `platform_z7.v` + the board_main XDC through a non-project Vivado flow
(synth → opt (`Explore`) → place (`ExtraTimingOpt`) → route (`MoreGlobalIterations`)) into
`/tmp/opencode/rev/pletdir`, and emits `timing_summary.rpt`, `util.rpt`, `hier.rpt`,
`route_status.rpt`, `control_sets.rpt`, `clocks.rpt` + `plet.dcp`.
This mirrors what the repo's own `build/*/gateware/platform_z7.tcl` does (same board files,
same part) but from the working tree, so structural effects (interconnect, CDC, branch
latches) are caught on top of the per-block sweeps.

## `hier_budget.py` — resource budget from a hierarchical utilization report

    python3 review/tools/hier_budget.py <utilization_hierarchical*.rpt> [out.md]

Parses `report_utilization -hierarchical` rows, groups them by hierarchy depth (indentation,
not string matching), ranks each depth by LUT, and prints device-relative utilization.
XC7Z010 budget: 17,600 LUT / 35,200 FF / 60 RAMB36-equiv / 80 DSP;
RAMB36-equiv = RAMB36 + RAMB18/2.

## `chain.sh` — the review's evidence chain (what produced the cited reports)

    bash review/tools/chain.sh
    # or: /tmp/opencode/rev/chain.sh           (same file; writes /tmp/opencode/rev/chain.log)

Runs, sequentially: plane @8 ns and @6.67 ns, blit_px @10 ns and @6.67 ns, video_mix @8 ns,
audio_soc @10 ns OOC sweeps, then the full-SoC build above. Per-sweep result dirs land in
`/tmp/opencode/rev/ooc/<block>_<period>/`; the full-SoC result lands in `/tmp/opencode/rev/pletdir/`.
Copy any `.rpt` you want to keep into `review/reports/` (that is how the committed evidence
was produced).

## Evidence dir conventions

- `review/reports/` — committed, curated `.rpt`-derived tables (per build, dated in text).
- `/tmp/opencode/rev/` — raw Vivado output (ooc dirs + pletdir). Kept until the review is done;
  the committed reports are what the review cites.

## `ooc_collect.py` — aggregate the OOC sweeps

    python3 review/tools/ooc_collect.py [/tmp/opencode/rev/ooc] > review/reports/ooc_summary.md

One row per sweep directory; fmax_est = 1000/(period − WNS) at post-route. The committed
`review/reports/ooc_summary.md` is the exact output of the 2026-10-20 chain.

## `route_wns.py` — per-clock post-route timing of the full SoC

    python3 review/tools/route_wns.py /tmp/opencode/rev/pletdir/timing_route.rpt \
        review/reports/soc_plet_timing.md

Parses column POSITIONS from the header line (blank cells for non-critical domains cannot shift
tokens), so it reads the SoC's whole Intra Clock Table (sys/comp/audio/HDMI domains) + the Clock
Summary (period/frequency per domain). The post-route `timing_route.rpt` itself is regenerated
from the route checkpoint by `finales.sh`-equivalent two-liner (open_checkpoint +
report_timing_summary); committed under `review/reports/plet/`.
