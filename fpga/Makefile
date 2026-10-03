# ZigMachine on an FPGA. Every target runs from fpga/; see README.md.
#   make setup     cores, Python env, sv2v + wasm2c (once)
#   make check     memmap + tests + SoC elaboration: the fpga/ gate
#   make util      LUT/FF/BRAM/DSP of each block on the 7-series
#   make carts     plan step 0a: every cart -> wasm2c -> rv32imf
#   make host      plan step 0b-i: native host running one cart (CART=stniccc)
#   make host-check  native host fingerprints == scene_hash.mjs, every cart
#   make video-sim CARTS=..  the cart CPU + the RTL video in Verilator vs scene_hash (cycles/video.mk)
#   make glass / sd  the ARM's program, the SD card (docs/FPGA_GLASS.md)
#   make vexgen-board  the z7 board's CPU netlists (soc/zm_z7.py; ZM_VEXGEN=1 tools/setup.sh once)
ZIG      ?= $(HOME)/.local/zig/0.16.0/zig
ROOT     := $(abspath ..)
MEMMAP   := $(ROOT)/machine/sdk/memmap.zig
EXPORT   := tools/memmap_export.zig
export PATH := $(CURDIR)/.tools/bin:$(CURDIR)/.tools/wabt/bin:$(PATH)

.PHONY: setup memmap test soc check util carts host host-check clean

setup:
	tools/setup.sh

gen/memmap.vh gen/memmap.py: $(MEMMAP) $(EXPORT)
	@mkdir -p gen
	$(ZIG) run --dep memmap -Mroot=$(EXPORT) -Mmemmap=$(MEMMAP) -- verilog gen/memmap.vh
	$(ZIG) run --dep memmap -Mroot=$(EXPORT) -Mmemmap=$(MEMMAP) -- python gen/memmap.py

# The glass (docs/FPGA_GLASS.md): its register map and the OSD font, generated
# like the memmap so the RTL, LiteX and the ARM program share one definition.
GLASS_MAP := glass/src/map.zig
GLASS_X   := $(ZIG) run --dep glass_map -Mroot=tools/glass_export.zig -Mglass_map=$(GLASS_MAP) --
FONT_RAW  := $(ROOT)/machine/assets/fonts/system_font_atari_1bit.raw
gen/glass_map.vh: $(GLASS_MAP) tools/glass_export.zig
	@mkdir -p gen
	$(GLASS_X) verilog $@
gen/glass_map.py: $(GLASS_MAP) tools/glass_export.zig
	@mkdir -p gen
	$(GLASS_X) python $@
gen/glass_font.vh: $(FONT_RAW) tools/glass_export.zig $(GLASS_MAP)
	@mkdir -p gen
	$(GLASS_X) font $(FONT_RAW) $@

memmap: gen/memmap.vh gen/memmap.py gen/glass_map.vh gen/glass_map.py gen/glass_font.vh

# One test run at a time, capped at 8 GB: the in-process (wasm) Yosys and the
# Verilator builds peak at several GB, and two concurrent runs sharing
# build/tests once OOM-killed a 13 GB pytest and the session with it.
TEST_MEM ?= 8G
test: memmap
	@mkdir -p build
	flock build/test.lock systemd-run --user --scope -q -p MemoryMax=$(TEST_MEM) -p MemorySwapMax=0 \
		uv run pytest -q

soc: memmap
	uv run python -m soc.zigmachine_soc --target sim

check: test soc
	@echo "fpga: check passed"

util: memmap
	uv run python tools/util.py

carts:
	tools/wasm2rv.sh

# The board's CPU (soc/zm_z7.py BOARD_CORE): sealed, 16 KiB 2-way I$, static branch
# prediction; and NOPRED_CORE, the same without prediction (+8 % fmax, +16-25 %
# cycles: CYCLES.md "Branch prediction and the clock"), for --cpu-netlist.
.PHONY: vexgen-board
vexgen-board:
	vexgen/gen.sh I16w2D4Seal:16384:2:4096:1:seal I16w2D4SealNopred:16384:2:4096:1:seal,nopred

# --- plan step 0b-i: the native host (host/README.md) ----------------------
# Every module goes through wasm2c with its own -n name; the host links
# machine + rom + one cart against one shared, bounds-checked memory.
WABT     := $(CURDIR)/.tools/wabt
W2C_RT   := $(WABT)/share/wabt/wasm2c
HOST     := build/host
CART     ?= stniccc
HOST_CC  ?= clang
# -ffp-contract=off: wasm never fuses a*b+c, and an FPU with fmadd (rv32 F)
# would otherwise round differently from the wasm machine.
HOST_CFLAGS := -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -ffp-contract=off -w -DWASM_RT_USE_MMAP=0 \
	-DWASM_RT_MEMCHECK_BOUNDS_CHECK=1 -DWASM_RT_MAX_CALL_STACK_DEPTH=10000 \
	-I$(WABT)/include -I$(W2C_RT) -Ihost -I$(HOST)/common
HOST_COMMON := $(addprefix $(HOST)/common/,machine.o rom.o rt.o rt-mem.o rt-exc.o sha256.o)

$(HOST)/common/machine.c: $(ROOT)/docs/machine-video.wasm
	@mkdir -p $(@D)
	wasm2c $< -n machine -o $@
$(HOST)/common/rom.c: $(ROOT)/docs/rom.wasm
	@mkdir -p $(@D)
	wasm2c $< -n rom -o $@
$(HOST)/common/rt.o: $(W2C_RT)/wasm-rt-impl.c
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@
$(HOST)/common/rt-mem.o: $(W2C_RT)/wasm-rt-mem-impl.c
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@
$(HOST)/common/rt-exc.o: $(W2C_RT)/wasm-rt-exceptions-impl.c
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@
$(HOST)/common/sha256.o: host/sha256.c host/sha256.h
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@
$(HOST)/common/%.o: $(HOST)/common/%.c
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@

.SECONDARY:
$(HOST)/%/cart.c: $(ROOT)/docs/demo-%.wasm
	@mkdir -p $(@D)
	wasm2c $< -n cart -o $@
$(HOST)/%/env.c: $(HOST)/%/cart.c $(HOST)/common/machine.c $(HOST)/common/rom.c tools/host_gen.py tools/wasm_info.py gen/memmap.py
	uv run python tools/host_gen.py --build $(HOST)/$* --cart $(ROOT)/docs/demo-$*.wasm
$(HOST)/%/cart.o: $(HOST)/%/cart.c
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c $< -o $@
$(HOST)/%/host.o: $(HOST)/%/env.c host/main.c host/boot.c host/host.h host/boot.h
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c $(HOST)/$*/env.c -o $(HOST)/$*/env.o
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c host/boot.c -o $(HOST)/$*/boot.o
	$(HOST_CC) $(HOST_CFLAGS) $(HOST_WALLCLOCK) -I$(HOST)/$* -c host/main.c -o $@
$(HOST)/%/host: $(HOST)/%/host.o $(HOST)/%/cart.o $(HOST_COMMON)
	$(HOST_CC) $(HOST)/$*/host.o $(HOST)/$*/env.o $(HOST)/$*/boot.o $(HOST)/$*/cart.o $(HOST_COMMON) -lm -lpthread -o $@

host: $(HOST)/$(CART)/host

host-check: memmap
	tools/host_check.sh $(CARTS)

include cycles/cycles.mk
include cycles/video.mk

# --- the glass: the ARM's program and the SD card (docs/FPGA_GLASS.md) -------
#   make glass   host build (glass sim-load / sim-menu) + the board's static ARM binary
#   make sd      stage the SD card in build/glass/sd (never a device; see its MANIFEST.txt)
.PHONY: glass sd
glass: memmap
	cd glass && $(ZIG) build
	cd glass && $(ZIG) build -Dtarget=arm-linux-musleabihf -Dcpu=cortex_a9 -Doptimize=ReleaseSafe --prefix zig-out/arm

sd: glass
	uv run python tools/glass_sd.py $(if $(BR_OUT),--buildroot $(BR_OUT))

clean:
	rm -rf build gen

# --- bitstreams: openXC7 in Docker (tools/openxc7.sh, docker/openxc7/) -------
#   make toolchain  the pinned image + prjxray-db + xc7z010 chipdb, into .tools/ (once, heavy)
#   make blink      first bitstream: rtl/board/blink_top.v -> build/blink/blink_top.bit
BOARD_XDC := boards/microphase_z7_7010/board.xdc
BLINK     := build/blink

.PHONY: toolchain blink

toolchain:
	tools/openxc7.sh toolchain

$(BLINK)/blink_top.xdc: rtl/board/blink_top.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

$(BLINK)/blink_top.bit: rtl/board/blink_top.v $(BLINK)/blink_top.xdc
	tools/openxc7.sh bit blink_top $(CURDIR)/$(BLINK) $(CURDIR)/$(BLINK)/blink_top.xdc $(CURDIR)/$<

blink: $(BLINK)/blink_top.bit
