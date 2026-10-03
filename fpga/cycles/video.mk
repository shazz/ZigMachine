# The video integration sim (Fable #9): the cycles firmware as the video
# sequencer (cycles/vmain.c + vseq.c) on soc/video_sim.py's SoC, where the RTL
# compositor does the machine's video. Included by fpga/Makefile after
# cycles/cycles.mk, whose wasm2c objects (`aligned`) it reuses: only what
# includes the SoC's CSR addresses (board, prof, env.c) is rebuilt.
#
#   make video-sim CARTS="tutorial union_main"     sims + report (tools/video_sim_run.py)
#   make video-fw CART=tutorial                     one image (and its no-drain mutant)
VCYC      := build/vcycles
SOC_VID   := build/soc_video
VID_DEPS  := soc/video_sim.py soc/zm_video_pipe.py soc/zm_video_dma.py soc/zm_video_snoop.py soc/zm_simram.py \
	soc/zm_memtiming.py soc/zm_cycles.py soc/zigmachine_soc.py rtl/sim/zm_memcfg.v $(wildcard rtl/video/*.v)
VRV_CFLAGS = $(subst -I$(CYC)/gen,-I$(VCYC)/gen,$(RV_CFLAGS)) -Ibuild/vdump $(V_aligned)
VFW_DEPS  := $(FW_DEPS) cycles/vboard.h $(VCYC)/gen/csr_addr.h build/vdump/zm_memmap.h
# drain: the sequencer as designed; nodrain: the mutant that issues passes
# before the CPU's stores have reached the compositor.
V_drain   :=
V_nodrain := -DZM_NO_DRAIN
# *_np: no span probes around the HBL handlers (env.c without prof.h). A probe
# reads six counters over the CSR bus after every handler, which is long enough
# to drain the stores itself and hide the race the drain rule closes; the board
# has no probes. The cycle split (cart / seq) is not measured in these builds.
V_drain_np   :=
V_nodrain_np := -DZM_NO_DRAIN
V_nocopy  := -DZM_NO_COPYBACK
V_linemajor := -DZM_LINE_MAJOR
P_linemajor := -include prof.h
P_drain := -include prof.h
P_nocopy := -include prof.h
P_nodrain := -include prof.h

$(SOC_VID)/video_sim.json: $(VID_DEPS)
	uv run python -m soc.video_sim >$(SOC_VID).log 2>&1 || (tail -20 $(SOC_VID).log; exit 1)
$(VCYC)/gen/csr_addr.h: $(SOC_VID)/video_sim.json tools/cycles_csr.py
	uv run python tools/cycles_csr.py --video $(SOC_VID)/csr.json $@
build/vdump/zm_memmap.h: gen/memmap.py tools/video_dump.py
	uv run python -c "import sys; sys.path.insert(0, 'tools'); import video_dump; video_dump.memmap_header()"

$(VCYC)/common/fw.a: $(VFW_DEPS)
	@mkdir -p $(@D)/fw
	for s in $(FW_FILES); do \
		$(RV_CC) $(VRV_CFLAGS) -c $$s -o $(@D)/fw/$$(basename $$s).o || exit 1; done
	rm -f $@ && $(RV_AR) rcs $@ $(@D)/fw/*.o

define video_rules
$(VCYC)/$(1)/%/fw.elf: $(CYC)/aligned/%/cart.o $(CYC)/aligned/common/machine.o $(CYC)/aligned/common/rom.o \
		$(VCYC)/common/fw.a $(HOST)/%/env.c host/boot.c cycles/vmain.c cycles/vseq.c FORCE
	@mkdir -p $$(@D)
	$(RV_CC) $(VRV_CFLAGS) -I$(HOST)/$$* $(P_$(1)) -c $(HOST)/$$*/env.c -o $$(@D)/env.o
	$(RV_CC) $(VRV_CFLAGS) -I$(HOST)/$$* -c host/boot.c -o $$(@D)/boot.o
	$(RV_CC) $(VRV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -c cycles/vseq.c -o $$(@D)/vseq.o
	$(RV_CC) $(VRV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -DZM_FRAMES=$(ZM_FRAMES) -DZM_EVERY=$(ZM_EVERY) \
		-DZM_CART='"$$*"' -c cycles/vmain.c -o $$(@D)/main.o
	$(RV_CC) $(RV_LDFLAGS) -o $$@ $$(@D)/main.o $$(@D)/vseq.o $$(@D)/env.o $$(@D)/boot.o $$< \
		$(CYC)/aligned/common/machine.o $(CYC)/aligned/common/rom.o $(VCYC)/common/fw.a -lm
# The video sim's RAM is 64 bits wide: one little-endian doubleword a line.
$(VCYC)/$(1)/%/main_ram.init: $(VCYC)/$(1)/%/fw.elf
	$(RV_OBJCOPY) -O binary $$< $$(@D)/fw.bin
	truncate -s %8 $$(@D)/fw.bin
	od -An -v -tx8 -w8 $$(@D)/fw.bin | tr -d ' ' >$$@
endef
$(foreach v,drain nodrain drain_np nodrain_np nocopy linemajor,$(eval $(call video_rules,$(v))))

.PHONY: video-sim video-fw
video-fw: $(VCYC)/drain/$(CART)/main_ram.init $(VCYC)/nodrain/$(CART)/main_ram.init
video-sim: memmap
	systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 uv run python tools/video_sim_run.py $(CARTS)
