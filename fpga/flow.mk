# The edit -> board loop (fpga/README.md "When is a full rebuild needed"). Included by the Makefile.
# Every build prints its per-stage times (tools/build_times.py) and appends a line to
# build/build_times.txt. P&R runs through tools/pnr_slot.sh: at most two openXC7 containers
# (6 GB each) on the box, slot 0 being the lock every other P&R target takes.
#
#   make bitstream             THE board's release bitstream, Vivado, the board's SoC parameters
#                              (soc/boards.py Board.soc, --release) -> build/<board>/release/ (BOARD=kestrel|peregrine)
#   make soc-z7                the openXC7 build: pinned seed (soc/openxc7.py SEED) -> build/<board>/soc_z7
#   make soc-dev               a stable-names build in build/soc_dev, REPLAYING the last one's placement
#                              when there is one (FRESH=1: place from scratch, a new base)
#   make sweep SEEDS="1 2 3 4" P&R of the last soc-z7 netlist (or SWEEP_SRC=<gateware dir>), 2 at a time
#   make hp-test               the HP-port probe bitstream -> build/hp_test/gateware/zm_hp_test.bit
SOC_ARGS  ?=
SEED      ?=
SEEDS     ?= 1 2 3 4
SWEEP_SRC ?= $(SOC_OUT)/gateware
DEV_OUT   := $(BOARD_BUILD)/soc_dev
RELEASE   := $(BOARD_BUILD)/release
# The box-wide Vivado lock is the MAIN checkout's (worktrees share it, like the board scripts).
VIVADO_LOCK := flock $(abspath $(shell git rev-parse --git-common-dir)/..)/fpga/build/vivado.lock
SLOT      := tools/pnr_slot.sh
SOC_RUN   := uv run --with meson --with ninja python -m soc.zigmachine_soc --target z7 --build
SOC_RUN_VIVADO := env PATH=/opt/vivado/2026.1/Vivado/bin:$$PATH LD_LIBRARY_PATH=$(HOME)/.local/lib/vivado-compat \
	uv run python -m soc.zigmachine_soc --target z7 --build --toolchain vivado
SOC_SEED   = $(if $(SEED),OPENXC7_SEED=$(SEED))
DEV_REUSE  = $(if $(and $(wildcard $(DEV_OUT)/gateware/platform_z7_placement.json),$(wildcard $(DEV_OUT)/gateware/stable_names),$(if $(FRESH),,x)),OPENXC7_REUSE=$(CURDIR)/$(DEV_OUT)/gateware)

.PHONY: bitstream soc-z7 soc-dev sweep hp-test

# One Vivado at a time on the box (~8 GB).
bitstream: memmap $(BOARD_CPU_CORE) $(BOARD_SOUND_CORE)
	@mkdir -p $(BOARD_BUILD)
	$(VIVADO_LOCK) $(SOC_RUN_VIVADO) --board $(BOARD) --release --out $(RELEASE) $(SOC_ARGS)

soc-z7: memmap
	$(SOC_SEED) $(SLOT) $(SOC_RUN) --out $(SOC_OUT) $(SOC_ARGS)

soc-dev: memmap
	OPENXC7_STABLE=1 $(DEV_REUSE) $(SOC_SEED) $(SLOT) $(SOC_RUN) --out $(DEV_OUT) $(SOC_ARGS)

sweep:
	uv run python tools/sweep.py $(SWEEP_SRC) --seeds $(SEEDS)

# Timing weight 10, not the SoC's 30: at 30 the small design crowds its band and router2 took
# 460 s to never-finished (900 s cap); at 10 it routes, 106 MHz (BUILD_LOOP.md "hp-test").
HPT_PNR := --placer-heap-congestion-spread --placer-heap-timingweight 10
hp-test: memmap
	OPENXC7_PNR_OPTS="$(HPT_PNR)" $(SOC_SEED) $(SLOT) uv run python -m soc.zm_hp_test --build

# The primitive self-test (rtl/board/prim_test_top.v): every primitive and mode the SoC uses, checked
# on silicon, results on GP0 (tools/prim_test_read.py; $(BOARD_DIR)/README.md "prim-test").
#   make prim-test   -> build/prim_test/prim_test_top.bit
#   make prim-allow  the allowlist (silicon_prims.json) against the board SoC's netlist (NETLIST=...)
PRIM_TEST   := build/prim_test
PRIM_TEST_V := rtl/board/prim_test_top.v $(sort $(wildcard rtl/board/prim_test/*.v))
NETLIST     ?= $(SOC_OUT)/gateware/platform_z7.json

.PHONY: prim-test prim-allow

$(PRIM_TEST)/prim_test_top.xdc: rtl/board/prim_test_top.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

$(PRIM_TEST)/prim_test_top.bit: $(PRIM_TEST_V) $(PRIM_TEST)/prim_test_top.xdc
	OPENXC7_PNR_OPTS="--placer-heap-congestion-spread" $(SLOT) tools/openxc7.sh bit prim_test_top \
		$(CURDIR)/$(@D) $(CURDIR)/$(@D)/prim_test_top.xdc $(addprefix $(CURDIR)/,$(PRIM_TEST_V))

prim-test: $(PRIM_TEST)/prim_test_top.bit

prim-allow:
	uv run python tools/prim_allowlist.py $(NETLIST)
