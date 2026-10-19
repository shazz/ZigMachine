# perf/fresco-linemajor: handoff (paused 2026-10-18)

## Done
- 124f9f99: the RTL `hold` / `keep` / `nopfb` bits and the sticky `dirty` / `filled` (zm_video_pass.v), the cmd CSR fields, the replay testbench's line-major mode.
  - tests/test_rtl_linemajor.py: 66 pass. All 7 RTL break tests are caught (`ZM_RTL_BREAK=1 ... -k broken`).
  - tests/test_video_order_group.py: 26 pass.
- WIP commit (compiled for the host only; the RISC-V firmware has never been compiled):
  - Firmware: cycles/bplanes.c, cycles/vseq_group.c, the FW_OPT switch bits in bdiag, the ZM_LINEMAJOR / ZM_LM_CHECK sim flags.
  - glass `run --fw-opt=N` (src/afi.zig sets HP1's WRCHAN). `zig build test` passes 106/106, and the ARM cross-build compiles.
  - `board_run.py --w64` (test_board_tools: 18 pass; test_run_happy[4] fails here only because build/board_hp/diag4_prefill.txt is missing in this worktree).
  - Docs: the decisions.md ADR, the PLANES_PLAN status, TESTING.md, the board README.
- Rule widened from the plan: every run of consecutive handler-free planes forms a group. The plan's literal rule gives an empty group for automation442, supplex_fs2, union_main, replicants, stcs and ancool, because each has a handler on plane 0.

## Left
1. Re-run tests/test_rtl_video.py in full, plus its 49 break tests with ZM_RTL_BREAK=1. Both runs were killed at the pause. Three mutants were retargeted: bg_rows_not_stored, mixed_rows_not_stored and fill_mix_row_not_stored.
2. Merge perf/ziggy-posted. decisions.md conflicts: the two branches append different ADRs, so keep both.
3. Build soc.hp_sim with `--out <own dir>` (and --posted 8 if the merge makes that the default). Then build the sim image for leonard with ZM_LM_CHECK=1 and run 2 frames under sim-a.lock. Expect "ZM LMCHK 2 same" and the scene_hash verdict.
4. Run Vivado with the board recipe (--blit --sound-cpu, the FPU netlist). Then run `cycles_csr.py --hp-check` against that build's csr.json (with --need-blit).
5. Build the board_snd_fpu system.rv32 (`make board-split ZM_AUDIO=snd ZM_FPU=1`), the glass ARM binary and a monolithic fw.bin for bdiag. Stage them with md5s and install steps.
6. W64 board test (U-Boot):
   - hp-test, using build/hp_test4/gateware/zm_hp_test.bit (current for the HP1 bridge): `mw.l 0xf8009014 0xf00`, then the HP1 bridge row write with CACHE=2 and its check.
   - `board_run.py --diag 3 --w64`.
   - Under Linux: `glass run --fw-opt=2`, then read vcal's W.
   - Rollback: reboot, or `glass run` without `--fw-opt`.

## Running
Nothing. No Vivado, no sim; the background pytest runs were stopped.
