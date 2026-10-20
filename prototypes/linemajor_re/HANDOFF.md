# perf/fresco-linemajor: handoff (staged for the board 2026-10-19)

## Done
- 124f9f99: the RTL `hold` / `keep` / `nopfb` bits and the sticky `dirty` / `filled` (zm_video_pass.v), the cmd CSR fields, the replay testbench's line-major mode.
- 8e9f541a: the firmware groups (cycles/bplanes.c, cycles/vseq_group.c), the FW_OPT switch bits in bdiag, glass `run --fw-opt=N`, `board_run.py --w64`, docs.
- ac507c7e: merged origin/main (f635ed98: perf/ziggy-posted, posted=8 is the board default). decisions.md keeps both ADRs.
- Tests on the merged tree (2026-10-19, logs in prototypes/linemajor_re/logs/):
  - tests/test_rtl_video.py: 78 pass (52 break tests skipped). Break run `ZM_RTL_BREAK=1 -k broken`: 52 of 52 mutants caught.
  - tests/test_rtl_linemajor.py + tests/test_video_order_group.py: 92 pass. Break run: 7 of 7 caught.
  - glass `zig build test`: 106/106.
  - The first full run failed 12 `test_recorded_frames_are_the_reference_hosts` cases: build/host/<tag>/host was never built in this worktree, and build/vdump/<tag> held frames recorded from the pre-merge carts. Fixed by `make host CART=<tag>` and deleting those dumps so they re-record. Not an RTL failure.
- The RISC-V firmware compiles: `make -o build/soc_hp/hp_sim.json board-split ZM_AUDIO=snd ZM_FPU=1` (table 1.2). bplanes.c and vseq_group.c are also clean under `-Wall -Wextra`.
  - `-o hp_sim.json` skips the Verilator compile of the board-SoC model (no SoC sims today). The sim's csr.json was elaborated from this tree. The `--hp-check` against the bitstream's map proves the addresses match.
- Vivado (build/board_lm8): the same tcl and xdc as 3ebb7381's board_posted8 (`--blit --sound-cpu --posted 8 --cpu-netlist build/vexgen/VexRiscv_I16w2D4SealFpu.v`, `set_param general.maxThreads 2` added by hand).
  - 15,035 LUT (85.43 %; posted baseline 15,045).
  - sys WNS +0.043 ns (baseline +0.011), comp +0.519. All clocks met.
  - CSR map identical to 3ebb7381's.
- `cycles_csr.py --hp-check build/board_lm8/csr.json --need-blit` passes, and its csr_addr.h is byte-identical to the firmware's.
- Staged in /home/matt/projects/ZigMachine/prototypes/linemajor_re/stage/ (INSTALL.txt has the md5s and steps):
  - zigmachine.bit 6261127d
  - system.rv32 6ada2908
  - glass dfb8afa6
  - fw_tutorial_bdiag.bin f2584bca (monolithic, for bdiag)

## Worktree setup a later agent will need
- Copy the submodule sources (rsync without .git) from the main checkout: third_party/jt49, fx68k, hdmi, neorv32.
- Copy boards/microphase_z7_7010/board.xdc (ignored by git).
- Copy build/vexgen/VexRiscv_SndNd.v from agent-ab658730c7d2f9a7a (same vexgen/ tree).

## W64 root cause (2026-10-19 night, decisions.md 2026-10-19)
- Not the RTL. HP1's AFI switched 32 -> 64 at run time (glass --fw-opt=2 after boot.cmd's 0xF01 and traffic)
  writes words 0 and 3 of every 16 bytes only; 64-bit from boot writes every word. 64 -> 32 at run time is fine.
- Fix: glass refuses W64 on a 32-bit channel (error.W64NeedsBoot); uboot_serial sets HP1 0xF00 in one write.
- Proof tools in prototypes/w64_re/: fbpeek.c (marker fill + per-word counts, on the board's Linux),
  fbcmp.c (picture vs picture), boot_w64.py (reboot + boot.cmd replayed with HP1 0xF00, serial only).
- Valid A/B: fpga/bench_results/2026-10-19_README.md (w64boot vs w32same).
- W64 IS THE DEFAULT since 2026-10-19 late (418fdebc, decisions.md "W64 is the board default"): boot.cmd sets
  HP1 0xF00, a plain `glass run` on 0xF00 runs W64, and the card's rootfs carries that glass
  (tools/rootfs_glass.py). A plain reboot needs no `cp` and no `gopt.sh`. Card now: boot.scr 96e29243,
  rootfs.cpio.uboot 2011585d (its /usr/bin/glass 82376563 = glass 0d23f3f6 stripped), glass 0d23f3f6.
  Backups on the card: boot.scr.bb67385d (HP1 0xf01), rootfs.cpio.uboot.31eeb461, glass.a896da36.
  Proof: prototypes/w64_re/proof_default.txt, default_boot_console.txt, bench_default/, fps_default/.
  A/B now: `/tmp/gopt.sh 0` (W32 arm, one way until reboot), a reboot brings W64 back.
  Rollback: restore boot.scr AND rootfs together (never the old rootfs alone); if Linux will not boot,
  `prototypes/w64_re/trial_boot.py rootfs.cpio.uboot.31eeb461 0xf01` from U-Boot over serial.

## Left (the lead)
1. Board: install per stage/INSTALL.txt. Read the OSD fps with no switches, then `--fw-opt=0x30` (the old order) on the same bitstream.
2. W64 (DONE 10-19 night, see above; the items below are superseded):
   - hp-test on HP1 (build/hp_test4/gateware/zm_hp_test.bit: `mw.l 0xf8009014 0xf00`, the HP1 bridge row write with CACHE=2 and its check).
   - `board_run.py --bit stage/zigmachine.bit --fw stage/fw_tutorial_bdiag.bin --blit --diag 3 --w64` (fw md5 f2584bca).
   - Then `glass run --fw-opt=2` and read vcal's W.
3. Not run: the ZM_LM_CHECK board-SoC sim (leonard, 2 frames, "ZM LMCHK 2 same"). Do it when sims are allowed again.

## Running
Nothing.
