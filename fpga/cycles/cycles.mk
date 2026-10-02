# Plan step 0b-ii: cycles per frame on a real VexRiscv (cycles/README.md).
# Included by fpga/Makefile, after the host rules it reuses (the wasm2c output
# and env.c of build/host/). Every build is one firmware image per cart and
# variant, loaded into the ONE Verilated SoC model (soc/cycles_sim.py).
#
#   make cycles CARTS="union_beatdis blitter"     sim + report (tools/cycles_run.py)
#   make cycles-fw CART=union_beatdis VARIANT=nobounds   one image only
RV_CC      ?= riscv64-unknown-elf-gcc
RV_OBJCOPY ?= riscv64-unknown-elf-objcopy
RV_AR      ?= riscv64-unknown-elf-ar
CYC        := build/cycles
SOC_CYC    := build/soc_cycles
ZM_FRAMES  ?= 60
ZM_EVERY   ?= 20
VARIANT    ?= nobounds
VARIANTS   := stock nobounds aligned float

# Same arithmetic as the native host (-ffp-contract=off: wasm never fuses).
# -fno-strict-aliasing: ZM_ALIGNED (zm_variant.h) moves floats through u32 pointers.
RV_ARCH    := -march=rv32im -mabi=ilp32 --specs=picolibc.specs
RV_CFLAGS  := $(RV_ARCH) -std=gnu11 -O2 -ffp-contract=off -fno-strict-aliasing -w \
	-DWASM_RT_USE_MMAP=0 -DWASM_RT_MEMCHECK_BOUNDS_CHECK=1 -DWASM_RT_MAX_CALL_STACK_DEPTH=10000 \
	-Icycles/shim -include rt_shim.h -I$(WABT)/include -I$(W2C_RT) -Icycles -Ihost \
	-I$(CYC)/gen -I$(HOST)/common
# main_ram (soc/cycles_sim.py): 16 MiB of code and constants, then 16 MiB of
# data, heap (the 7 MiB wasm memory is calloc'd there) and a 1 MiB stack. The
# script comes AFTER the --defsym's, or it reads __stack_size as undefined.
RV_LDFLAGS := $(RV_ARCH) -Wl,--defsym=__flash=0x40000000,--defsym=__flash_size=0x01000000 \
	-Wl,--defsym=__ram=0x41000000,--defsym=__ram_size=0x01000000,--defsym=__stack_size=0x00100000 \
	-Tpicolibc.ld
V_stock    :=
V_nobounds := -DZM_NO_BOUNDS
V_aligned  := -DZM_NO_BOUNDS -DZM_ALIGNED
V_float    := -DZM_NO_BOUNDS -DZM_FCOUNT
comma      := ,
# fcount.c's FOPS table IS the wrap list: one -Wl,--wrap per X(routine, ...).
L_float     = $(addprefix -Wl$(comma)--wrap=,$(shell grep -oE 'X.[_a-z0-9]+,' cycles/fcount.c | sed -E 's/^X.//; s/,$$//' | sort -u))

$(SOC_CYC)/cycles_sim.json: soc/cycles_sim.py soc/zm_cycles.py soc/zigmachine_soc.py soc/litex_compat.py
	uv run python -m soc.cycles_sim >$(SOC_CYC).log 2>&1 || (tail -20 $(SOC_CYC).log; exit 1)
$(CYC)/gen/csr_addr.h: $(SOC_CYC)/cycles_sim.json tools/cycles_csr.py
	uv run python tools/cycles_csr.py $(SOC_CYC)/csr.json $@

# wasm2c output with zm_variant.h spliced in where wasm2c's memory macros end.
SPLICE := /^\/\/ When using guard pages, reads have to be immediately consumed/i \#include "zm_variant.h"
define splice
	@mkdir -p $(@D)
	grep -q '^// When using guard pages, reads have to be immediately consumed' $< || \
		(echo "cycles: wasm2c output changed, zm_variant.h has no splice point in $<"; exit 1)
	sed '$(SPLICE)' $< >$@
endef
$(CYC)/src/%.c: $(HOST)/common/%.c cycles/zm_variant.h
	$(splice)
$(CYC)/src/%/cart.c: $(HOST)/%/cart.c cycles/zm_variant.h
	$(splice)

# The firmware around the modules: board, owners, traps, float counters, the
# STOCK wasm2c runtime (through cycles/shim) and the native host's sha256.
FW_FILES := $(addprefix cycles/,board.c prof.c trap.c trap.S fcount.c) host/sha256.c \
	$(addprefix $(W2C_RT)/,wasm-rt-impl.c wasm-rt-mem-impl.c wasm-rt-exceptions-impl.c)
FW_DEPS  := $(FW_FILES) $(wildcard cycles/*.h cycles/shim/*.h cycles/shim/sys/*.h)

# One variant's rules: common objects, then per-cart objects, image and init.
define variant_rules
$(CYC)/$(1)/common/machine.o: $(CYC)/src/machine.c $(CYC)/gen/csr_addr.h
	@mkdir -p $$(@D)
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -c $$< -o $$@
$(CYC)/$(1)/common/rom.o: $(CYC)/src/rom.c
	@mkdir -p $$(@D)
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -c $$< -o $$@
$(CYC)/$(1)/common/fw.a: $(FW_DEPS) $(CYC)/gen/csr_addr.h
	@mkdir -p $$(@D)/fw
	for s in $(FW_FILES); do \
		$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -c $$$$s -o $$(@D)/fw/$$$$(basename $$$$s).o || exit 1; done
	rm -f $$@ && $(RV_AR) rcs $$@ $$(@D)/fw/*.o
$(CYC)/$(1)/%/cart.o: $(CYC)/src/%/cart.c
	@mkdir -p $$(@D)
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -c $$< -o $$@
$(CYC)/$(1)/%/fw.elf: $(CYC)/$(1)/%/cart.o $(CYC)/$(1)/common/machine.o $(CYC)/$(1)/common/rom.o \
		$(CYC)/$(1)/common/fw.a $(HOST)/%/env.c host/boot.c cycles/main.c FORCE
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -include prof.h -c $(HOST)/$$*/env.c -o $$(@D)/env.o
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -c host/boot.c -o $$(@D)/boot.o
	$(RV_CC) $(RV_CFLAGS) $(V_$(1)) -I$(HOST)/$$* -DZM_FRAMES=$(ZM_FRAMES) -DZM_EVERY=$(ZM_EVERY) \
		-DZM_CART='"$$*"' -c cycles/main.c -o $$(@D)/main.o
	$(RV_CC) $(RV_LDFLAGS) $(L_$(1)) -o $$@ $$(@D)/main.o $$(@D)/env.o $$(@D)/boot.o $$< \
		$(CYC)/$(1)/common/machine.o $(CYC)/$(1)/common/rom.o $(CYC)/$(1)/common/fw.a -lm
$(CYC)/$(1)/%/main_ram.init: $(CYC)/$(1)/%/fw.elf
	$(RV_OBJCOPY) -O binary $$< $$(@D)/fw.bin
	od -An -v -tx4 -w4 $$(@D)/fw.bin | tr -d ' ' >$$@
endef
$(foreach v,$(VARIANTS),$(eval $(call variant_rules,$(v))))

.PHONY: cycles cycles-fw cycles-sim FORCE
FORCE:
cycles-sim: $(SOC_CYC)/cycles_sim.json $(CYC)/gen/csr_addr.h
cycles-fw: cycles-sim $(CYC)/$(VARIANT)/$(CART)/main_ram.init
cycles: cycles-sim memmap
	uv run python tools/cycles_run.py $(CARTS)
