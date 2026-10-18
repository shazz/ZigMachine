# The first cart on the board: cycles/bmain.c (the sequencer firmware) on the
# board SoC, main RAM in PS DDR over HP0 and the video DMA over HP1
# (soc/zm_board_mem.py). Included by fpga/Makefile after cycles.mk and
# video.mk, whose wasm2c objects (`aligned`) and memmap header it reuses.
#
#   make hp-sim CART=tutorial          soc/hp_sim.py (the board SoC with a model of the PS) in Verilator:
#                                      the frame hashes against apps/scene_hash.mjs (tools/hp_sim_run.py)
#   make board-fw CART=tutorial        build/hcycles/board/<cart>/fw.bin: the image U-Boot loads to DDR
#   make board-shelf [ZM_AUDIO=snd]    board-fw for every cart of the SD card's shelf (tools/glass_sd.py SHELF)
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
# ZM_FPU (cycles/cycles.mk): the hardware-float images, in build/hcycles/{sim,board}_fpu/.
HCYC     := build/hcycles
SOC_HP   := build/soc_hp
ZM_BLIT  ?= hw
HP_DEPS  := soc/hp_sim.py soc/zm_board_mem.py soc/zm_hp.py soc/zm_simaxi.py soc/zm_video_axi.py \
	soc/zm_blit_soc.py soc/zm_blit_hp.py $(wildcard rtl/blitter/*.v) \
	soc/zm_z7.py soc/zm_glass.py $(VID_DEPS) $(wildcard rtl/glass/*.v) \
	soc/zm_audio_soc.py $(wildcard rtl/audio/*.v) rtl/sim/zm_audio_tap.v
HRV_CFLAGS = $(subst -I$(CYC)/gen,-I$(HCYC)/gen,$(RV_CFLAGS)) -Ibuild/vdump $(V_$(HV)) -Iglass/firmware -Igen
HFW_FILES := $(filter-out cycles/board.c,$(FW_FILES)) cycles/bboard.c cycles/bmailbox.c cycles/bdiag.c cycles/bblit.c cycles/bdisk.c \
	host/glass_router.c
# The glass's input into the cart, and GEM's data disk (bdiskapp.c): per cart, as env.c (they see
# the cart's w2c_env through host.h).
HIN_SRC := cycles/binput.c cycles/bcursor.c host/input_bridge.c cycles/bdiskapp.c
HFW_DEPS  := $(FW_DEPS) cycles/bmicros.h cycles/bdisk.c cycles/bblit.c cycles/bblit.h cycles/bboard.c cycles/bboard.h cycles/bmailbox.c cycles/bmailbox.h cycles/bdiag.c cycles/bdiag.h cycles/vboard.h $(HCYC)/gen/csr_addr.h build/vdump/zm_memmap.h \
	cycles/binput.c cycles/binput.h cycles/bcursor.c cycles/bcursor.h host/input_bridge.c host/input_bridge.h host/glass_router.c \
	cycles/bdiskapp.c cycles/bdiskapp.h cycles/bcartreq.h host/disk_app.h host/zmd_dir.h host/zmd_dir_fat.h gen/glass_cart.h \
	glass/firmware/glass_input.c glass/firmware/glass_input.h gen/glass_map.h
# The link of cycles.mk with the top 4 KiB of the window kept free for the debug
# mailbox (cycles/bmailbox.h): the stack starts below it.
HRV_LDFLAGS := $(subst __ram_size=0x01000000,__ram_size=0x00fff000,$(RV_LDFLAGS)) -Wl,--wrap=w2c_machine_hwBlit $(L_$(HV))
# ZM_AUDIO=snd: the cart's data ends at 28 MiB, the sound CPU's starts there (cycles/sound.mk).
HRV_LDFLAGS_snd := $(subst __ram_size=0x01000000,__ram_size=0x00C00000,$(RV_LDFLAGS)) -Wl,--wrap=w2c_machine_hwBlit $(L_$(HV))
B_hw     := -DZM_BLIT_HW
B_sw     :=
# sim: hash and end; board: run forever, report to the glass, print nothing.
# ZM_AUDIO=snd: the players on the sound CPU (cycles/sound.mk); this image starts it and forwards
# the cart's songs (cycles/bsound.c), for a bitstream built with the sound CPU.
ZM_AUDIO ?= 1
A_0      := -DZM_NO_AUDIO
AUD_CART_SRC_1   := $(AUD_FW_SRC)
AUD_CART_SRC_0   := $(AUD_FW_SRC)
AUD_CART_SRC_snd := host/audio_bridge.c cycles/bsound.c
AUD_CART_OBJ_1   := $(CYC)/$(HV)/common/aplayer.o
AUD_CART_OBJ_0   := $(CYC)/$(HV)/common/aplayer.o
AUD_CART_OBJ_snd := $(HCYC)/snd/play/snd_img.o
HRV_LDFLAGS_1    := $(HRV_LDFLAGS)
HRV_LDFLAGS_0    := $(HRV_LDFLAGS)
# ZM_AUDIO=snd images go to build/hcycles/{sim,board}_snd/: never over the cart-CPU-audio ones.
ASUF_snd := _snd
ASUF     := $(ASUF_$(ZM_AUDIO))
ZM_WARP_MS ?= 0
ZM_TRACE_FRAME ?= 0
# ZM_SIM_KEYS=F:event,... (sim only): the glass's key FIFO as a script (cycles/binput.c), the
# native host's ZM_GLASS_KEYS, so a sim can press the keys the board's input would.
# ZM_SIM_POINTER=F:word,... (sim only): the mouse the same way (ZM_GLASS_POINTER).
# ZM_MODES (sim only): several of a cart's modes in one hp sim (cycles/bmain.c).
ZM_MODES ?=
H_sim    = -DZM_FRAMES=$(ZM_FRAMES) -DZM_EVERY=$(ZM_EVERY) -DZM_WARP_MS=$(ZM_WARP_MS) -DZM_TRACE_FRAME=$(ZM_TRACE_FRAME) \
	$(B_$(ZM_BLIT)) $(A_$(ZM_AUDIO)) $(if $(ZM_SIM_KEYS),'-DZM_SIM_KEYS="$(ZM_SIM_KEYS)"') \
	$(if $(ZM_SIM_POINTER),'-DZM_SIM_POINTER="$(ZM_SIM_POINTER)"') $(if $(ZM_MODES),-DZM_MODES=$(ZM_MODES))
# ZM_SYS_MHZ=<n>: a bitstream whose sys clock is not 100 MHz (the FPU test bitstream runs 80):
# board_micros() (bboard.c, the cart's hostMicros) is the one place the firmware reads the clock.
ZM_SYS_MHZ ?=
H_board  = -DZM_BOARD -DZM_FRAMES=0 -DZM_EVERY=1 $(B_$(ZM_BLIT)) $(A_$(ZM_AUDIO)) $(if $(ZM_SYS_MHZ),-DZM_SYS_MHZ=$(ZM_SYS_MHZ)u)

$(SOC_HP)/hp_sim.json: $(HP_DEPS)
	systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 \
		uv run python -m soc.hp_sim >$(SOC_HP).log 2>&1 || (tail -20 $(SOC_HP).log; exit 1)
# The board SoC with the f32 FPU cart core (the ZM_FPU=1 images' sim: tools/hp_sim_run.py --fpu).
# Same SoC, same CSR map: only the core netlist differs.
FPU_CORE := build/vexgen/VexRiscv_I16w2D4SealFpu.v
$(SOC_HP)_fpu/hp_sim.json: $(HP_DEPS) $(FPU_CORE)
	systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 \
		uv run python -m soc.hp_sim --core $(FPU_CORE) --out $(SOC_HP)_fpu >$(SOC_HP)_fpu.log 2>&1 || (tail -20 $(SOC_HP)_fpu.log; exit 1)
$(FPU_CORE):
	vexgen/gen.sh I16w2D4SealFpu:16384:2:4096:1:seal,fpu
# The bitstream's CSR map: elaboration only (no toolchain), the same SoC as --build.
build/soc_z7/csr.json: $(HP_DEPS) soc/zigmachine_soc.py
	uv run python -m soc.zigmachine_soc --target z7 $(if $(filter hw,$(ZM_BLIT)),--blit) >build/soc_z7.log 2>&1 \
		|| (tail -20 build/soc_z7.log; exit 1)
$(HCYC)/gen/csr_addr.h: $(SOC_HP)/hp_sim.json build/soc_z7/csr.json tools/cycles_csr.py
	uv run python tools/cycles_csr.py --hp $(SOC_HP)/csr.json $@ --hp-check build/soc_z7/csr.json \
		$(if $(filter hw,$(ZM_BLIT)),--need-blit)

# env.hostMicros (cycles/bmicros.h): the board's images have the clock; the sim's answer 0, as the
# native host and scene_hash.mjs do, so a benchmark cart does its FIXED work a frame and its
# hashes compare (apps/zig/scenes/raytrace/bench.zig). Its rate in the sim is cycles/frame.
MICROS_board := -include bmicros.h
MICROS_sim   :=
# The cart's stream imports (zg.audioStreamStart / audioFeed / audioStreamStop) reach the stream
# ring wherever the players run (host/hstream.h); ZM_AUDIO=0 keeps the stub's no-op.
STREAM_1   := -include host/hstream.h
STREAM_snd := -include host/hstream.h
STREAM_0   :=
define hp_rules
# The clock fw.a was built for: rewritten only when ZM_SYS_MHZ changes, so fw.a follows it.
$(HCYC)/$(1)$(ASUF)$(HSUF)/common/sys_mhz: FORCE
	@mkdir -p $$(@D)
	@echo '$(ZM_SYS_MHZ)' | cmp -s - $$@ || echo '$(ZM_SYS_MHZ)' >$$@
$(HCYC)/$(1)$(ASUF)$(HSUF)/common/fw.a: $(HFW_DEPS) $(HCYC)/$(1)$(ASUF)$(HSUF)/common/sys_mhz
	@mkdir -p $$(@D)/fw
	for s in $(HFW_FILES); do \
		$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -c $$$$s -o $$(@D)/fw/$$$$(basename $$$$s).o || exit 1; done
	rm -f $$@ && $(RV_AR) rcs $$@ $$(@D)/fw/*.o
$(HCYC)/$(1)$(ASUF)$(HSUF)/%/fw.elf: $(CYC)/$(HV)/%/cart.o $(CYC)/$(HV)/common/machine.o $(CYC)/$(HV)/common/rom.o \
		$(HCYC)/$(1)$(ASUF)$(HSUF)/common/fw.a $(HOST)/%/env.c host/boot.c cycles/bmain.c cycles/vseq.c \
		$(AUD_FW_DEPS) $(HCYC)/songs/%.c $(AUD_CART_OBJ_$(ZM_AUDIO)) FORCE
	@mkdir -p $$(@D)
	rm -f $$(@D)/aud_*.o
	for s in $(AUD_CART_SRC_$(ZM_AUDIO)) $(HCYC)/songs/$$*.c; do \
		$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -I$(HOST)/$$* -c $$$$s -o $$(@D)/aud_$$$$(basename $$$$s .c).o || exit 1; done
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* $(MICROS_$(1)) $(STREAM_$(ZM_AUDIO)) -c $(HOST)/$$*/env.c -o $$(@D)/env.o
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* -c host/boot.c -o $$(@D)/boot.o
	$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/$$* -c cycles/vseq.c -o $$(@D)/vseq.o
	for s in $(HIN_SRC); do $(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -I$(HOST)/$$* -c $$$$s -o $$(@D)/in_$$$$(basename $$$$s .c).o || exit 1; done
	$(RV_CC) $(HRV_CFLAGS) $(H_$(1)) -I$(HOST)/$$* -DZM_CART='"$$*"' -c cycles/bmain.c -o $$(@D)/main.o
	$(RV_CC) $(HRV_LDFLAGS_$(ZM_AUDIO)) -o $$@ $$(@D)/main.o $$(@D)/vseq.o $$(@D)/env.o $$(@D)/boot.o $$(@D)/in_*.o $$< \
		$$(@D)/aud_*.o $(AUD_CART_OBJ_$(ZM_AUDIO)) \
		$(CYC)/$(HV)/common/machine.o $(CYC)/$(HV)/common/rom.o $(HCYC)/$(1)$(ASUF)$(HSUF)/common/fw.a -lm
# fw.bin is what lands at DDR_BASE (soc/zm_hp.py): the CPU's reset vector is its first word.
$(HCYC)/$(1)$(ASUF)$(HSUF)/%/fw.bin: $(HCYC)/$(1)$(ASUF)$(HSUF)/%/fw.elf
	$(RV_OBJCOPY) -O binary $$< $$@
	truncate -s %8 $$@
	test $$$$(stat -c %s $$@) -lt 12582912 || (echo "$$@: over 12 MiB, it would overlap the pictures"; exit 1)
endef
$(foreach v,sim board,$(eval $(call hp_rules,$(v))))

# The DDR model is 64 bits wide: one little-endian doubleword a line. With the cart's
# shelf disk where ZWINDOW puts it, when docs/ has one (tools/ddr_init.py, cycles/bdisk.c).
$(HCYC)/sim$(ASUF)$(HSUF)/%/zm_ddr.init: $(HCYC)/sim$(ASUF)$(HSUF)/%/fw.bin tools/ddr_init.py
	uv run python tools/ddr_init.py $< $@ $(if $(wildcard $(ROOT)/docs/demo-$*.zmd),--disk $(ROOT)/docs/demo-$*.zmd)

.PHONY: hp-sim board-fw board-shelf soc-hp-fpu
soc-hp-fpu: $(SOC_HP)_fpu/hp_sim.json
board-fw: memmap $(HCYC)/board$(ASUF)$(HSUF)/$(CART)/fw.bin
	@ls -l $(HCYC)/board$(ASUF)$(HSUF)/$(CART)/fw.bin
board-shelf: memmap
	for c in $$(uv run python tools/glass_sd.py --shelf); do $(MAKE) --no-print-directory board-fw CART=$$c || exit 1; done
hp-sim: memmap
	uv run python tools/hp_sim_run.py $(CART)
