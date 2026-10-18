# The board's split images (decisions.md 2026-10-15): ONE system image per variant (firmware,
# machine, ROM, BARD's image) and a lean image per cart, bound by the versioned table of
# cycles/sys_abi.txt. glass writes both (glass/src/loader.zig). Included by fpga/Makefile after
# sound.mk, whose BARD blob and board.mk's fw.a, flags and songs it reuses.
#
#   make board-split [ZM_AUDIO=snd]     build/hcycles/split/board<suf>/sys.bin + carts<fpu>/<cart>/cart.bin,
#                                       for every cart of the shelf (tools/glass_sd.py --shelf)
#   make split-cart CART=tutorial       one lean cart image
#   make split-sys-sim ZM_AUDIO=snd     the sim's system image (hashing, ZM_FRAMES/ZM_EVERY), for
#                                       tools/hp_sim_run.py --split
#   ZM_CART_VERSION=0x20000u            (split-cart) a cart claiming another table version: the
#                                       refusal test (tests/test_cart_split.py, hp_sim_run.py --abi-skew)
#
# The cart image does not depend on sim/board or ZM_AUDIO: the sim runs the very image the
# card carries. It is built from the same spliced wasm2c output as the monolithic cart.o, with
# no TLS (-D_Thread_local=: its call-depth counter is its own, the ADR says why).
SPLIT       := $(HCYC)/split
SPL_CFLAGS   = $(HRV_CFLAGS) -DZM_SPLIT_SYS
CART_CFLAGS  = $(RV_CFLAGS) $(V_$(HV)) -DZM_SPLIT_CART -D_Thread_local= -Igen \
	$(if $(ZM_CART_VERSION),-DZM_CART_VERSION=$(ZM_CART_VERSION))
CART_BASE    = 0x$(shell printf '%08x' $$(( $(shell awk '/define CART_CPU_BASE/{print $$3}' gen/glass_map.h | tr -d u) \
	+ $(shell awk '/define CART_IMG_AT/{print $$3}' gen/glass_cart.h | tr -d u) )))
CART_LDFLAGS = $(filter-out --specs=picolibc.specs,$(RV_ARCH)) $(L_$(HV)) -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments \
	-Wl,--defsym=ZM_CART_BASE=$(CART_BASE) -Tcycles/cart.ld
CARTS_DIR   := $(SPLIT)/carts$(HSUF)$(if $(ZM_CART_VERSION),_v$(ZM_CART_VERSION))
SYS_ABI_DEPS := cycles/sys_abi.txt $(wildcard tools/sys_abi*.py) tools/wasm_sig.py tools/host_bridges.py \
	tools/host_gen.py glass/src/map_cart.zig host/host.h cycles/baudio.h $(ROOT)/docs/rom.wasm \
	$(ROOT)/docs/machine-video.wasm

gen/zm_sys_abi.h: $(SYS_ABI_DEPS)
	uv run python tools/sys_abi_c.py header $@
gen/zm_cart_rt.c: $(SYS_ABI_DEPS)
	uv run python tools/sys_abi_c.py cart-rt $@
$(HOST)/common/sys_env.c: $(HOST)/common/machine.c $(HOST)/common/rom.c tools/host_split.py tools/host_bridges.py \
		gen/zm_sys_abi.h gen/memmap.py
	uv run python tools/host_split.py system $@
$(HOST)/%/cart_env.c: $(HOST)/%/cart.c $(HOST)/common/machine.c $(HOST)/common/rom.c tools/host_split.py \
		gen/zm_sys_abi.h gen/memmap.py
	uv run python tools/host_split.py cart $(HOST)/$* --cart $(ROOT)/docs/demo-$*.wasm

# One lean cart image: cart.c, its env, the shared runtime forwarders, its songs; libgcc only.
$(CARTS_DIR)/%/cart.elf: $(CYC)/src/%/cart.c $(HOST)/%/cart_env.c gen/zm_cart_rt.c $(HCYC)/songs/%.c \
		cycles/cart.ld gen/zm_sys_abi.h cycles/baudio.h host/host.h FORCE
	@mkdir -p $(@D)
	$(RV_CC) $(CART_CFLAGS) -I$(HOST)/$* -c $(CYC)/src/$*/cart.c -o $(@D)/cart.o
	for s in $(HOST)/$*/cart_env.c gen/zm_cart_rt.c $(HCYC)/songs/$*.c; do \
		$(RV_CC) $(CART_CFLAGS) -I$(HOST)/$* -c $$s -o $(@D)/$$(basename $$s .c).o || exit 1; done
	$(RV_CC) $(CART_LDFLAGS) -o $@ $(@D)/cart.o $(@D)/cart_env.o $(@D)/zm_cart_rt.o $(@D)/$*.o -lgcc
$(CARTS_DIR)/%/cart.bin: $(CARTS_DIR)/%/cart.elf
	$(RV_OBJCOPY) -O binary $< $@
	truncate -s %8 $@

# The system image of a variant: board.mk's firmware with the cart taken out (bsys.c binds it).
define split_rules
$(SPLIT)/$(1)$(ASUF)$(HSUF)/sys.elf: $(HCYC)/$(1)$(ASUF)$(HSUF)/common/fw.a $(HOST)/common/sys_env.c cycles/bsys.c \
		cycles/bsys.h cycles/bsys_abi.h cycles/bmain.c cycles/vseq.c $(VPLAN_SRC) $(AUD_FW_DEPS) $(AUD_CART_OBJ_$(ZM_AUDIO)) \
		$(CYC)/$(HV)/common/machine.o $(CYC)/$(HV)/common/rom.o gen/zm_sys_abi.h $(HFW_DEPS) FORCE
	@mkdir -p $$(@D)/o
	rm -f $$(@D)/o/*.o
	for s in $(AUD_CART_SRC_$(ZM_AUDIO)) $(HIN_SRC); do \
		$(RV_CC) $(SPL_CFLAGS) $(H_$(1)) -c $$$$s -o $$(@D)/o/s_$$$$(basename $$$$s .c).o || exit 1; done
	$(RV_CC) $(SPL_CFLAGS) $(MICROS_$(1)) $(STREAM_$(ZM_AUDIO)) -c $(HOST)/common/sys_env.c -o $$(@D)/o/sys_env.o
	$(RV_CC) $(SPL_CFLAGS) -c cycles/vseq.c -o $$(@D)/o/vseq.o
	for s in $(VPLAN_SRC); do $(RV_CC) $(SPL_CFLAGS) $(H_$(1)) -c $$$$s -o $$(@D)/o/$$$$(basename $$$$s .c).o || exit 1; done
	$(RV_CC) $(SPL_CFLAGS) -c cycles/bsys.c -o $$(@D)/o/bsys.o
	$(RV_CC) $(SPL_CFLAGS) $(H_$(1)) -c cycles/bmain.c -o $$(@D)/o/main.o
	$(RV_CC) $(HRV_LDFLAGS_$(ZM_AUDIO)) -o $$@ $$(@D)/o/*.o $(AUD_CART_OBJ_$(ZM_AUDIO)) \
		$(CYC)/$(HV)/common/machine.o $(CYC)/$(HV)/common/rom.o $(HCYC)/$(1)$(ASUF)$(HSUF)/common/fw.a -lm
$(SPLIT)/$(1)$(ASUF)$(HSUF)/sys.bin: $(SPLIT)/$(1)$(ASUF)$(HSUF)/sys.elf
	$(RV_OBJCOPY) -O binary $$< $$@
	truncate -s %8 $$@
	@# the shell call runs with the recipe, not at eval: in a fresh tree, memmap makes gen/glass_cart.h first
	test $$$$(stat -c %s $$@) -le $$$$(( $$(shell awk '/define CART_IMG_AT/{print $$$$3}' gen/glass_cart.h | tr -d u) )) \
		|| (echo "$$@: past CART_IMG_AT, it would overlap the cart image"; exit 1)
endef
$(foreach v,sim board,$(eval $(call split_rules,$(v))))

.PHONY: board-split split-cart split-sys-sim
split-cart: memmap $(CARTS_DIR)/$(CART)/cart.bin
	@ls -l $(CARTS_DIR)/$(CART)/cart.bin
split-sys-sim: memmap $(SPLIT)/sim$(ASUF)$(HSUF)/sys.bin
board-split: memmap $(SPLIT)/board$(ASUF)$(HSUF)/sys.bin
	for c in $$(uv run python tools/glass_sd.py --shelf); do $(MAKE) --no-print-directory split-cart CART=$$c || exit 1; done
	@ls -l $(SPLIT)/board$(ASUF)$(HSUF)/sys.bin
