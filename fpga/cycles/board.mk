# The first cart on the board: cycles/bmain.c (the sequencer firmware) on the
# board SoC, main RAM in PS DDR over HP0 and the video DMA over HP1
# (soc/zm_board_mem.py). Included by fpga/Makefile after cycles.mk and
# video.mk, whose wasm2c objects (`aligned`) and memmap header it reuses.
#
#   make hp-sim CART=tutorial          soc/hp_sim.py (the board SoC with a model of the PS) in Verilator:
#                                      the frame hashes against apps/scene_hash.mjs (tools/hp_sim_run.py)
#   make board-fw CART=tutorial        build/hcycles/board/<cart>/fw.bin: the image U-Boot loads to DDR
#
# One image is linked for one CSR map: the header comes from the sim's csr.json,
# and tools/cycles_csr.py --hp-check refuses it if the bitstream's map differs.
#
# ZM_BLIT=hw (default): hwBlit() runs on rtl/blitter's zm_blit over HP2 (cycles/bblit.c,
# soc/zm_blit_soc.py), so the bitstream must be built with --blit; ZM_BLIT=sw: the
# machine's software blitter, for a bitstream without it (and the SW figures).
# ZM_AUDIO=1 (default): the players run on the cart CPU into the audio core (cycles/baudio.c,
# cycles/audio.mk); ZM_AUDIO=0: no music (the figures without it). The bitstream has the core
# unless built with --no-audio.
HCYC     := build/hcycles
SOC_HP   := build/soc_hp
ZM_BLIT  ?= hw
HP_DEPS  := soc/hp_sim.py soc/zm_board_mem.py soc/zm_hp.py soc/zm_simaxi.py soc/zm_video_axi.py \
	soc/zm_blit_soc.py soc/zm_blit_hp.py $(wildcard rtl/blitter/*.v) \
	soc/zm_z7.py soc/zm_glass.py $(VID_DEPS) $(wildcard rtl/glass/*.v) \
	soc/zm_audio_soc.py $(wildcard rtl/audio/*.v) rtl/sim/zm_audio_tap.v
HRV_CFLAGS = $(subst -I$(CYC)/gen,-I$(HCYC)/gen,$(RV_CFLAGS)) -Ibuild/vdump $(V_aligned)
HFW_FILES := $(filter-out cycles/board.c,$(FW_FILES)) cycles/bboard.c cycles/bmailbox.c cycles/bdiag.c cycles/bblit.c
HFW_DEPS  := $(FW_DEPS) cycles/bmicros.h cycles/bblit.c cycles/bblit.h cycles/bboard.c cycles/bboard.h cycles/bmailbox.c cycles/bmailbox.h cycles/bdiag.c cycles/bdiag.h cycles/vboard.h $(HCYC)/gen/csr_addr.h build/vdump/zm_memmap.h
# The link of cycles.mk with the top 4 KiB of the window kept free for the debug
# mailbox (cycles/bmailbox.h): the stack starts below it.
HRV_LDFLAGS := $(subst __ram_size=0x01000000,__ram_size=0x00fff000,$(RV_LDFLAGS)) -Wl,--wrap=w2c_machine_hwBlit
B_hw     := -DZM_BLIT_HW
B_sw     :=
# sim: hash and end; board: run forever, report to the glass, print nothing.
ZM_AUDIO ?= 1
A_0      := -DZM_NO_AUDIO
H_sim    = -DZM_FRAMES=$(ZM_FRAMES) -DZM_EVERY=$(ZM_EVERY) $(B_$(ZM_BLIT)) $(A_$(ZM_AUDIO))
H_board  = -DZM_BOARD -DZM_FRAMES=0 -DZM_EVERY=1 $(B_$(ZM_BLIT)) $(A_$(ZM_AUDIO))

$(SOC_HP)/hp_sim.json: $(HP_DEPS)
	systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 \
		uv run python -m soc.hp_sim >$(SOC_HP).log 2>&1 || (tail -20 $(SOC_HP).log; exit 1)
# The bitstream's CSR map: elaboration only (no toolchain), the same SoC as --build.
build/soc_z7/csr.json: $(HP_DEPS) soc/zigmachine_soc.py
	uv run python -m soc.zigmachine_soc --target z7 $(if $(filter hw,$(ZM_BLIT)),--blit) >build/soc_z7.log 2>&1 \
		|| (tail -20 build/soc_z7.log; exit 1)
$(HCYC)/gen/csr_addr.h: $(SOC_HP)/hp_sim.json build/soc_z7/csr.json tools/cycles_csr.py
	uv run python tools/cycles_csr.py --hp $(SOC_HP)/csr.json $@ --hp-check build/soc_z7/csr.json \
		$(if $(filter hw,$(ZM_BLIT)),--need-blit)

define hp_rules
$(HCYC)/$(1)/common/fw.a: $(HFW_DEPS)
	@mkdir -p $$(@D)/fw
	for s in $(HFW_FILES); do \
		$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -c $$$$s -o $$(@D)/fw/$$$$(basename $$$$s).o || exit 1; done
	rm -f $$@ && $(RV_AR) rcs $$@ $$(@D)/fw/*.o
$(HCYC)/$(1)/%/fw.elf: $(CYC)/aligned/%/cart.o $(CYC)/aligned/common/machine.o $(CYC)/aligned/common/rom.o \
		$(HCYC)/$(1)/common/fw.a $(HOST)/%/env.c host/boot.c cycles/bmain.c cycles/vseq.c \
		$(AUD_FW_DEPS) $(HCYC)/songs/%.c FORCE
	@mkdir -p $$(@D)
	for s in $(AUD_FW_SRC) $(HCYC)/songs/$$*.c; do \
		$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -I$(HOST)/$$* -c $$$$s -o $$(@D)/aud_$$$$(basename $$$$s .c).o || exit 1; done
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* -include bmicros.h -c $(HOST)/$$*/env.c -o $$(@D)/env.o
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* -c host/boot.c -o $$(@D)/boot.o
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* -c cycles/vseq.c -o $$(@D)/vseq.o
	$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -I$(HOST)/$$* -DZM_CART='"$$*"' -c cycles/bmain.c -o $$(@D)/main.o
	$(RV_CC) $(HRV_LDFLAGS) -o $$@ $$(@D)/main.o $$(@D)/vseq.o $$(@D)/env.o $$(@D)/boot.o $$< \
		$$(@D)/aud_*.o $(CYC)/aligned/common/aplayer.o \
		$(CYC)/aligned/common/machine.o $(CYC)/aligned/common/rom.o $(HCYC)/$(1)/common/fw.a -lm
# fw.bin is what lands at DDR_BASE (soc/zm_hp.py): the CPU's reset vector is its first word.
$(HCYC)/$(1)/%/fw.bin: $(HCYC)/$(1)/%/fw.elf
	$(RV_OBJCOPY) -O binary $$< $$@
	truncate -s %8 $$@
	test $$$$(stat -c %s $$@) -lt 12582912 || (echo "$$@: over 12 MiB, it would overlap the pictures"; exit 1)
endef
$(foreach v,sim board,$(eval $(call hp_rules,$(v))))

# The DDR model is 64 bits wide: one little-endian doubleword a line.
$(HCYC)/sim/%/zm_ddr.init: $(HCYC)/sim/%/fw.bin
	od -An -v -tx8 -w8 $< | tr -d ' ' >$@

.PHONY: hp-sim board-fw
board-fw: memmap $(HCYC)/board/$(CART)/fw.bin
	@ls -l $(HCYC)/board/$(CART)/fw.bin
hp-sim: memmap
	uv run python tools/hp_sim_run.py $(CART)
