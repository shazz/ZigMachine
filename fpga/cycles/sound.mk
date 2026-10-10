# The sound CPU's firmware (cycles/sound/, docs/FPGA_SOUND_CPU.md) and the cart images that
# start it. Included by fpga/Makefile after board.mk, whose CSR header and fw.a it reuses.
#
#   make snd-fw                          build/hcycles/snd/play/snd.bin: the players, driven by the
#                                        cart's mailbox commands (one image for every cart)
#   make hp-sim CART=tutorial ZM_AUDIO=snd   the cart on the cart CPU, its music on the sound CPU
#                                        (board.mk; needs the soc_hp_snd model: make soc-hp-snd)
#   make snd-bench SONG=union/wow_scroller.sndh [TUNE=0] [ZM_FRAMES=8]
#                                        one song on the sound CPU, no cart: cycles a frame
#   ZM_SOC=$PWD/build/soc_hp_snd ZM_INIT=sim_zm_ddr.init tools/cycles_sim.sh \
#       build/hcycles/snd/bench/zm_ddr.init /dev/shm/sb
#
# The link: code at SND_BASE (14 MiB into the cart window, above the pictures, at most 2 MiB),
# data, heap (the players' 3 MiB) and a 256 KiB stack in the window's top 4 MiB, under the
# console ring and the debug mailbox page (cycles/snd_mailbox.h). The cart's own data moves
# down to 16-28 MiB (board.mk HRV_LDFLAGS with ZM_AUDIO=snd).
SND        := $(HCYC)/snd
SOC_SND    := build/soc_hp_snd
SND_CORE   := build/vexgen/VexRiscv_Snd.v
SND_LDFLAGS := $(RV_ARCH) -Wl,--defsym=__flash=0x40E00000,--defsym=__flash_size=0x00200000 \
	-Wl,--defsym=__ram=0x41C00000,--defsym=__ram_size=0x003EF000,--defsym=__stack_size=0x00040000 \
	-Tpicolibc.ld
SND_CFLAGS  = $(HRV_CFLAGS) -Icycles/sound -I$(HOST)/tutorial -DZM_SND
SND_COMMON := cycles/sound/sboard.c cycles/trap.c cycles/trap.S \
	$(addprefix $(W2C_RT)/,wasm-rt-impl.c wasm-rt-mem-impl.c wasm-rt-exceptions-impl.c)
SND_PLAY   := host/audio.c host/audio_imports.c cycles/baudio.c cycles/sound/smain.c
SND_DEPS   := $(SND_COMMON) $(SND_PLAY) cycles/bsongs.c $(wildcard cycles/sound/*.h) cycles/snd_mailbox.h \
	$(AUD_HDRS) cycles/baudio.h $(CYC)/aligned/common/aplayer.o $(HOST)/common/aplayer.h \
	$(HCYC)/gen/csr_addr.h $(HOST)/tutorial/cart.h

# One sound image: $(1) = its name (play | bench), $(2) = extra sources, $(3) = extra flags.
define snd_image
$(SND)/$(1)/snd.elf: $(SND_DEPS) $(2) FORCE
	@mkdir -p $$(@D)/o
	for s in $(SND_COMMON) $(SND_PLAY) $(2); do \
		$(RV_CC) $(SND_CFLAGS) $(3) -c $$$$s -o $$(@D)/o/$$$$(basename $$$$s).o || exit 1; done
	$(RV_CC) $(SND_LDFLAGS) -o $$@ $$(@D)/o/*.o $(CYC)/aligned/common/aplayer.o -lm
$(SND)/$(1)/snd.bin: $(SND)/$(1)/snd.elf
	$(RV_OBJCOPY) -O binary $$< $$@
	test $$$$(stat -c %s $$@) -le 2097152 || (echo "$$@: over 2 MiB, it would overlap the cart's data"; exit 1)
# The blob the cart image links (cycles/bsound.c: _binary_snd_bin_start/_end).
$(SND)/$(1)/snd_img.o: $(SND)/$(1)/snd.bin
	cd $$(@D) && $(RV_OBJCOPY) -I binary -O elf32-littleriscv -B riscv \
		--rename-section .data=.rodata,alloc,load,readonly,data,contents snd.bin snd_img.o
endef

SONG ?= sos.sndh
TUNE ?= 0
$(SND)/bench/songs.c: tools/song_pack.py FORCE
	@mkdir -p $(@D)
	printf 'L 0 0 %s\n' '$(SONG)' >$(@D)/song.w
	uv run python tools/song_pack.py $(ROOT)/docs/demo-tutorial.wasm $@ --log $(@D)/song.w
$(eval $(call snd_image,play,))
$(eval $(call snd_image,bench,cycles/bsongs.c $(SND)/bench/songs.c,-DZM_SND_BENCH '-DZM_SONG="$(SONG)"' \
	-DZM_TUNE=$(TUNE) -DZM_FRAMES=$(ZM_FRAMES)))

# The bench's cart side (cycles/sound/sbench_cart.c): start the bench image, print its console, end.
$(SND)/bench/fw.elf: $(SND)/bench/snd_img.o cycles/sound/sbench_cart.c cycles/bsound.c host/audio_bridge.c \
		$(HCYC)/sim/common/fw.a FORCE
	for s in cycles/sound/sbench_cart.c cycles/bsound.c host/audio_bridge.c; do \
		$(RV_CC) $(SND_CFLAGS) -c $$s -o $(@D)/c_$$(basename $$s .c).o || exit 1; done
	$(RV_CC) $(HRV_LDFLAGS_snd) -o $@ $(@D)/c_*.o $< $(HCYC)/sim/common/fw.a -lm
$(SND)/bench/zm_ddr.init: $(SND)/bench/fw.elf
	$(RV_OBJCOPY) -O binary $< $(@D)/fw.bin && truncate -s %8 $(@D)/fw.bin
	od -An -v -tx8 -w8 $(@D)/fw.bin | tr -d ' ' >$@

$(SOC_SND)/hp_sim.json: $(HP_DEPS) soc/zm_sound_cpu.py soc/zm_sound_regs.py rtl/sim/zm_snd_putc.v $(SND_CORE)
	systemd-run --user --scope -q -p MemoryMax=6G -p MemorySwapMax=0 \
		uv run python -m soc.hp_sim --sound-cpu --out $(SOC_SND) >$(SOC_SND).log 2>&1 || (tail -20 $(SOC_SND).log; exit 1)
$(SND_CORE):
	vexgen/gen.sh Snd:16384:2:4096:1:snd

.PHONY: snd-fw snd-bench soc-hp-snd
snd-fw: memmap $(SND)/play/snd.bin
	@ls -l $(SND)/play/snd.bin
snd-bench: memmap $(SND)/bench/zm_ddr.init
soc-hp-snd: $(SOC_SND)/hp_sim.json
