# ZIGGY read bypass: handoff (2026-10-19)

Branch `perf/ziggy-read-bypass`, from origin/main f635ed98. Worktree
`.claude/worktrees/ziggy-read-bypass`. Stopped before Vivado. No SoC sim was run.

## What it does

The posted HP0 bridge (`fpga/soc/zm_hp_posted.py`) made a store 2.25 cycles, but every read
waited for `idle`: the buffer empty and every B answered. With `read_bypass`
(`fpga/soc/zm_hp_bypass.py`, wired in `WishboneHP._bypass`):

- A **burst** read (a D$ or I$ refill) is sent at once, unless a store to the **same 32-byte
  line** is still unanswered. In that case it waits for the drain, as before.
- **Tags live from push to B**, not to issue. The ring forgets an address when the store leaves
  for AW/W, but the store is only in DDR at its B. So there are 16 slots (8 buffered + 8 in flight),
  each a 20-bit line tag (the line within the 32 MiB window). The brief's "8 comparators"
  undercounts: an issued store is still not in DDR (see the `retire_on_issue` break test).
- A **single** (classic) read keeps the full drain. IO loads never reach this bridge, and the
  IOFence (`idle`) is untouched. So the brief's "IO read must drain" became "classic reads drain;
  IO loads stay unfenced as the 10-18 ADR chose". `test_io_fence.py` runs unchanged, and a doorbell
  test runs with the bypass on. **Veto point for the lead.**
- **The compare is registered**, to keep it off the AR path (sys WNS was +0.011 ns). With stores
  pending, a refill starts one cycle after its request, on the registered compare of that same
  request (`waited` = the request was already there last cycle). With no stores pending, it
  starts at once as before.
- On by default for the board and its sim: `zm_board_mem.READ_BYPASS = True`.
  `--no-read-bypass` on `zigmachine_soc --target z7` and on `hp_sim` turns it off. BARD
  (`zm_sound_cpu.py`) keeps the class default, off.

## Numbers

| | drained (today) | bypass |
|---|---:|---:|
| memcpy model, c/B (`tests/test_hp_bypass_rate.py`) | 2.78 | **2.25** (x1.24) |
| board mc.lib.64K, c/B (BENCH_REPORTS 10-18) | 2.73 | expected ~2.2, to be measured |

The model port answers a write 18 cycles after its AW (the board's measured blocking store).
It sends a read's first beat 20 cycles after its AR (hp_sim's HP_LATENCY), which makes a refill
~47 cycles (the board's ld.miss is 48). Its drained memcpy, 2.78 c/B, matches the board's 2.73.

LUT/FF estimate (yosys `synth_xilinx`, the bridge alone, posted=8;
`prototypes/read_bypass_re/lut_estimate.py [tag bits]`, run from `fpga/`; no Vivado was used):

| | LUT | FF |
|---|---:|---:|
| bypass off | 182 | 425 |
| bypass on, 20-bit tags | 476 (**+294**) | 771 (+346) |
| bypass on, 12-bit tags | 363 (+181) | 643 (+218) |

Vivado usually packs tighter than yosys. The board is at 15,045 LUT (85.5 %).

## Tests (all in `fpga/`, `uv run pytest -q ...`)

The brief asked for a Verilator unit bench in the style of `test_rtl_*.py`. The bridge is Migen
with no Verilog of its own to drive, so these benches use Migen's simulator, in the style of the
`test_hp_posted.py` and `test_io_fence.py` that already cover this module. The break tests use
the same `ZM_RTL_BREAK=1` gate as `test_rtl_*.py`.

- `tests/test_hp_bypass.py`: a model port (`tests/hp_port_model.py`) records every AR together
  with the stores still unanswered. The invariant is that no AR leaves for a line that has an
  unanswered store, whatever the RAM model's write timing (`zm_simaxi` writes at W-accept, so a
  data check alone cannot see a too-early retire). The file also checks that an other-line refill
  goes out with 4+ stores unanswered, that the same refill drains without the bypass, that a
  single read drains, RAW data on the slow-write DDR model, the IO doorbell with the bypass on,
  and that a bad mutant name or a bypass without `posted` is rejected.
- `tests/test_hp_bypass_rate.py`: the memcpy model above (bypass <= 0.85 x drained).
- Break tests (`ZM_RTL_BREAK=1`), each one failing as required:
  - `nocompare`: the stale RAW word, plus 3 scenarios.
  - `headonly`: the "same line, behind older unanswered stores" scenario.
  - `retire_on_issue`: 3 scenarios.
  - `nowait`: "same line, right after a refill of another line".
  - `classic_too`: a single read goes out with stores pending.
- Bridge suite (bypass, rate, posted, posted_rate, io_fence, board_mem): 38 passed and 6 skipped
  without `ZM_RTL_BREAK`; 44 passed with `ZM_RTL_BREAK=1`. `test_prim_allowlist` and
  `test_sound_regs` (which build the SoC) pass on the final tree: 10 passed, 1 skipped.
- Board gateware elaborates (`--target z7 --toolchain vivado --blit`, no toolchain run). There are
  `st_tag` registers in the Verilog, and none with `--no-read-bypass`.

## Risks, in order

1. **LUT and timing.** The estimate is +~300 LUT at 85.5 % utilisation with +0.011 ns WNS. The
   compare is registered, but the tag write and the 16 x 20-bit compare are new logic near
   the bridge. Fallbacks: build with `--no-read-bypass`, or narrow `LINE_TAG` (in
   `zm_hp_bypass.py`: a false match only drains, so it stays correct, at about -110 LUT for
   12 bits). A per-line-run tag (memcpy's 8 stores in one slot) would cut comparators further,
   but it was not built.
2. **hp_sim now defaults ON and was not run today** (no SoC sims). Hash one cart on the sim
   before the bitstream, or pass `--no-read-bypass` to keep the old sim.
3. **Store→load reordering is now visible to other masters**, for different lines only. It
   breaks only a Dekker-style DDR protocol. A grep of `fpga/cycles` finds only IO-register polls;
   the DDR handoffs are data-then-flag stores, whose order is unchanged.
4. **The `waited` gate assumes** a master never swaps its request without an ack in back-to-back
   cycles. VexRiscv holds a request until its ack, and the LiteX arbiter needs a cycle with cyc
   low to switch masters. The `nowait` break test pins the gate.
5. `headonly` is only caught while the older store is still unanswered at the refill (B_LAT 18
   against 7 pushes). It holds in the bench as written.
6. `fpga/soc/zigmachine_soc.py` was already over 200 lines and grew by 3 (the CLI flag).
   `soc/zm_hp.py` has a pre-existing ruff I001; it was left alone.

## Files

- `fpga/soc/zm_hp_bypass.py` (new): StoreTags and the mutants.
- `fpga/soc/zm_hp.py`: `read_bypass`, `break_`, `_bypass`, and `rwait` in the read start.
- `fpga/soc/zm_hp_posted.py`: exposes `issue`.
- `fpga/soc/zm_board_mem.py`, `zm_z7.py`, `zigmachine_soc.py`, `hp_sim.py`: `READ_BYPASS`
  and `--no-read-bypass`.
- `fpga/tests/hp_port_model.py`, `test_hp_bypass.py`, `test_hp_bypass_rate.py` (new);
  `test_hp_posted.py` and `test_io_fence.py` (Bench parameters only).
- `decisions.md`: the 2026-10-19 ADR (including the AXI ordering argument), and a pointer from
  the 10-18 ADR's stale consequence.

## Next

The lead builds the bitstream (Vivado LUT/WNS), then the bench cart A/B: `mc.lib.64K`,
`raw.miss`, `ld.miss`, and fr.* unchanged. If timing fails, `--no-read-bypass` restores today's
build exactly.
