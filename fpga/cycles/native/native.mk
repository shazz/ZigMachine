# Native KESTREL carts (decisions.md 2026-10-17): lean cart images written for ZIGGY directly,
# in C or RV32 assembly, not compiled from wasm. Board only: the browser cannot run them.
# They are called exactly as split.mk's wasm2c carts are (cycles/bsys.c, the zm_cart_hdr of
# gen/zm_sys_abi.h), so the system image is unchanged. Included by fpga/Makefile after split.mk.
#
#   make native-cart NAME=hello [ZM_FPU=1]      build/hcycles/split/native<fpu>/hello/{cart.bin,disk.zmd}
#   make native-cart NAME=hello_asm             the same cart by hand (cycles/native/hello_asm.S)
#
# cart.bin is checked as glass and bsys.c will (tools/native_cart.py check); disk.zmd is the
# shelf disk glass_sd.py fattens with it (--fw-dir build/hcycles/split/native<fpu>): its wasm
# boot cart only tells a browser the disk is KESTREL-only.
NATIVE       := $(SPLIT)/native$(HSUF)
NATIVE_FLAGS  = $(filter-out --specs=picolibc.specs,$(RV_ARCH)) $(L_$(HV)) -Os -ffreestanding -nostdlib \
	-fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -Icycles -Icycles/native -Igen -Ibuild/vdump
NATIVE_DEPS  := cycles/native/native.h cycles/native/native_check.c cycles/cart.ld gen/zm_sys_abi.h \
	build/vdump/zm_memmap.h
NATIVE_TITLE_hello     := HELLO WORLD (C)
NATIVE_TITLE_hello_asm := HELLO WORLD (ASM)

# native_check.c first: the plain numbers the assembly uses, against the generated header.
define native_link
	@mkdir -p $(@D)
	$(RV_CC) $(NATIVE_FLAGS) -fsyntax-only cycles/native/native_check.c
	$(RV_CC) $(NATIVE_FLAGS) -c $< -o $(@D)/cart.o
	$(RV_CC) $(CART_LDFLAGS) -o $@ $(@D)/cart.o
endef
$(NATIVE)/%/cart.elf: cycles/native/%.c $(NATIVE_DEPS)
	$(native_link)
$(NATIVE)/%/cart.elf: cycles/native/%.S $(NATIVE_DEPS)
	$(native_link)
$(NATIVE)/%/cart.bin: $(NATIVE)/%/cart.elf tools/native_cart.py
	$(RV_OBJCOPY) -O binary $< $@
	truncate -s %8 $@
	uv run python tools/native_cart.py check $@ || (rm -f $@; exit 1)
$(NATIVE)/%/disk.zmd: $(NATIVE)/%/cart.bin cycles/native/browser_stub.c
	uv run python tools/native_cart.py disk $< $@ --title "$(or $(NATIVE_TITLE_$*),$*)"

.PHONY: native-cart
native-cart: memmap $(NATIVE)/$(NAME)/cart.bin $(NATIVE)/$(NAME)/disk.zmd
	@ls -l $(NATIVE)/$(NAME)/cart.bin $(NATIVE)/$(NAME)/disk.zmd
