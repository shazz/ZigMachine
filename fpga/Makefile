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
#   make soc-z7 / soc-dev / sweep / hp-test  bitstreams, fast loop: flow.mk, README.md "When is a full rebuild needed"
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
# The map as C, for the cart CPU's firmware (fpga/glass/firmware/glass_input.c, host/input_bridge.c):
# every upper-case integer of glass_map.py, as tests/test_glass.py passes them with -D.
gen/glass_map.h: gen/glass_map.py
	uv run python -c "import runpy; v = runpy.run_path('$<'); \
		print('/* GENERATED from gen/glass_map.py by fpga/Makefile. Do not edit. */\n#ifndef ZM_GLASS_MAP_H\n#define ZM_GLASS_MAP_H'); \
		[print(f'#define {k} {x:#x}u') for k, x in v.items() if k.isupper() and isinstance(x, int)]; print('#endif')" >$@
# The cart swap's words (glass/src/map_cart.zig): software between ZWINDOW and ZIGGY, so
# Python and C only (no .vh: nothing in the PL reads them).
GLASS_CART := glass/src/map_cart.zig
gen/glass_cart.py: $(GLASS_CART) tools/glass_export.zig
	@mkdir -p gen
	$(ZIG) run --dep glass_map -Mroot=tools/glass_export.zig -Mglass_map=$(GLASS_CART) -- python $@
gen/glass_cart.h: gen/glass_cart.py
	uv run python -c "import runpy; v = runpy.run_path('$<'); \
		print('/* GENERATED from gen/glass_cart.py by fpga/Makefile. Do not edit. */\n#ifndef ZM_GLASS_CART_H\n#define ZM_GLASS_CART_H'); \
		[print(f'#define {k} {x:#x}u') for k, x in v.items() if k.isupper() and isinstance(x, int)]; print('#endif')" >$@
gen/glass_font.vh: $(FONT_RAW) tools/glass_export.zig $(GLASS_MAP)
	@mkdir -p gen
	$(GLASS_X) font $(FONT_RAW) $@

memmap: gen/memmap.vh gen/memmap.py gen/glass_map.vh gen/glass_map.py gen/glass_map.h gen/glass_font.vh \
	gen/glass_cart.py gen/glass_cart.h

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
$(HOST)/%/env.c: $(HOST)/%/cart.c $(HOST)/common/machine.c $(HOST)/common/rom.c tools/host_gen.py tools/host_bridges.py \
		tools/wasm_info.py gen/memmap.py
	uv run python tools/host_gen.py --build $(HOST)/$* --cart $(ROOT)/docs/demo-$*.wasm
$(HOST)/%/cart.o: $(HOST)/%/cart.c
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c $< -o $@
# The board firmware's input router (host/input_bridge.c + glass_router.c), so ZM_GLASS_KEYS tests it.
INPUT_SRC := host/input_bridge.c host/glass_router.c
INPUT_DEPS := $(INPUT_SRC) host/input_bridge.h glass/firmware/glass_input.c glass/firmware/glass_input.h gen/glass_map.h
INPUT_CFLAGS := -Iglass/firmware -Igen
# The native host's scripted inputs (--call, --disk, ZM_GLASS_KEYS / ZM_GLASS_POINTER).
HOST_IO := host/host_io.c host/host_io.h
$(HOST)/%/host.o: $(HOST)/%/env.c host/main.c host/boot.c host/host.h host/boot.h host/disk.h $(HOST_IO) $(INPUT_DEPS) \
		host/disk_app.h host/zmd_dir.h host/zmd_dir_fat.h
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c $(HOST)/$*/env.c -o $(HOST)/$*/env.o
	$(HOST_CC) $(HOST_CFLAGS) -I$(HOST)/$* -c host/boot.c -o $(HOST)/$*/boot.o
	$(HOST_CC) $(HOST_CFLAGS) $(INPUT_CFLAGS) -I$(HOST)/$* -c host/host_io.c -o $(HOST)/$*/host_io.o
	for s in $(INPUT_SRC); do $(HOST_CC) $(HOST_CFLAGS) $(INPUT_CFLAGS) -I$(HOST)/$* -c $$s -o $(HOST)/$*/in_$$(basename $$s .c).o || exit 1; done
	$(HOST_CC) $(HOST_CFLAGS) $(HOST_WALLCLOCK) $(INPUT_CFLAGS) -I$(HOST)/$* -c host/main.c -o $@
$(HOST)/%/host: $(HOST)/%/host.o $(HOST)/%/cart.o $(HOST_COMMON)
	$(HOST_CC) $(HOST)/$*/host.o $(HOST)/$*/env.o $(HOST)/$*/boot.o $(HOST)/$*/host_io.o $(HOST)/$*/in_*.o \
		$(HOST)/$*/cart.o $(HOST_COMMON) -lm -lpthread -o $@

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

#   make hdmi-test      second bitstream: HDMI1 test pattern, 800x600@60 -> build/hdmi_test/hdmi_test_top.bit
#   make hdmi-test-sim  the pattern in CXXRTL, checked, frames 0 and 60 -> build/hdmi_test/frame_*.png
#   make hdmi-test-VARIANT  bring-up variants -> build/hdmi_test_VARIANT/hdmi_test_top.bit:
#     oddr     10:1 by a fabric shifter + ODDR instead of the OSERDESE2 cascade (zm_dvi_out's default)
#     clkonly  no serialiser: the 40 MHz pixel clock on the clock pair (ODDR), data pairs constant
#     rev      symbols sent MSB first          inv  the three data pairs inverted (P/N swapped)
#     lvcmos   as oddr, but every pair as two LVCMOS33 outputs (P, ~P): no TMDS_33 driver
# Every P&R takes Fable's container lock (one openXC7 container at a time on this box).
HDMI_TEST := build/hdmi_test
HDMI_TEST_V := rtl/board/hdmi_test_top.v rtl/board/hdmi_pattern.v rtl/board/hdmi_dvi_dbg.v \
	rtl/video/zm_vtiming.v rtl/video/zm_dvi_out.v rtl/video/zm_tmds_enc.v rtl/video/zm_tmds_shift.v
HDMI_LOCK := flock $(CURDIR)/build/fable_timing3/.container.lock
HDMI_DEFS_oddr    := -DHDMI_ODDR
HDMI_DEFS_clkonly := -DHDMI_CLKONLY
HDMI_DEFS_rev     := -DHDMI_REVERSE
HDMI_DEFS_inv     := -DHDMI_INVERT
HDMI_DEFS_lvcmos  := -DHDMI_ODDR -DHDMI_SE
HDMI_XDC_lvcmos   := | sed 's/TMDS_33/LVCMOS33/'
HDMI_VARIANTS := oddr clkonly rev inv lvcmos

.PHONY: hdmi-test hdmi-test-sim $(addprefix hdmi-test-,$(HDMI_VARIANTS))

build/hdmi_test%/hdmi_test_top.xdc: rtl/board/hdmi_test_top.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< $(HDMI_XDC$(subst /,,$*)) > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

build/hdmi_test%/hdmi_test_top.bit: $(HDMI_TEST_V) gen/memmap.vh build/hdmi_test%/hdmi_test_top.xdc
	OPENXC7_DEFS="$(HDMI_DEFS$(subst /,,$*))" $(HDMI_LOCK) tools/openxc7.sh bit hdmi_test_top $(CURDIR)/$(@D) \
		$(CURDIR)/$(@D)/hdmi_test_top.xdc $(addprefix $(CURDIR)/,$(HDMI_TEST_V))

hdmi-test: $(HDMI_TEST)/hdmi_test_top.bit
$(addprefix hdmi-test-,$(HDMI_VARIANTS)): hdmi-test-%: build/hdmi_test_%/hdmi_test_top.bit

hdmi-test-sim: memmap
	uv run python tools/hdmi_test_sim.py 60

#   make edid-test        third bitstream: the monitor's EDID read over HDMI1's DDC, shown on HDMI1 as hex
#                         -> build/edid_test/edid_test_top.bit; decode a transcription with tools/edid_decode.py
#   make hdmi-audio-test  fourth: HDMI with sound, the test pattern + 440/660 Hz tones at 48 kHz in data islands
#                         -> build/hdmi_audio/hdmi_audio_top.bit
# Both are simulated by `make test` (tests/tb/edid_core_tb.cpp, tests/tb/hdmi_audio_tb.cpp). Like hdmi-test they
# take the container lock themselves; under an outer `flock <that lock> make ...` pass HDMI_LOCK= to skip it.
HDMI_SER_V := rtl/board/hdmi_clk.v rtl/video/zm_dvi_out.v rtl/video/zm_tmds_enc.v rtl/video/zm_tmds_shift.v
EDID_TEST_V := rtl/board/edid_test_top.v rtl/board/edid_core.v rtl/board/edid_i2c.v rtl/board/edid_reader.v \
	rtl/board/edid_text.v rtl/video/zm_vtiming.v $(HDMI_SER_V)
HDMI_AUDIO_V := rtl/board/hdmi_audio_top.v rtl/board/hdmi_audio_core.v rtl/board/hdmi_pattern.v rtl/board/hdmi_tone.v \
	rtl/video/zm_vtiming.v $(wildcard rtl/hdmi/zm_hdmi_*.v) $(HDMI_SER_V)

.PHONY: edid-test hdmi-audio-test

build/edid_test/%.xdc build/hdmi_audio/%.xdc: rtl/board/%.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

build/edid_test/edid_test_top.bit: $(EDID_TEST_V) gen/memmap.vh gen/glass_font.vh build/edid_test/edid_test_top.xdc
	$(HDMI_LOCK) tools/openxc7.sh bit edid_test_top $(CURDIR)/$(@D) $(CURDIR)/$(@D)/edid_test_top.xdc \
		$(addprefix $(CURDIR)/,$(EDID_TEST_V))

build/hdmi_audio/hdmi_audio_top.bit: $(HDMI_AUDIO_V) gen/memmap.vh build/hdmi_audio/hdmi_audio_top.xdc
	$(HDMI_LOCK) tools/openxc7.sh bit hdmi_audio_top $(CURDIR)/$(@D) $(CURDIR)/$(@D)/hdmi_audio_top.xdc \
		$(addprefix $(CURDIR)/,$(HDMI_AUDIO_V))

edid-test: build/edid_test/edid_test_top.bit
hdmi-audio-test: build/hdmi_audio/hdmi_audio_top.bit

#   make osd-test      fifth bitstream: the glass OSD over the test pattern, its registers on the PS's GP0 at
#                      0x43C0_0000 -> build/osd_test/osd_test_top.bit; drive it from U-Boot: tools/osd_uboot_demo.sh
#   make osd-test-sim  its logic in CXXRTL through the demo's steps, every pixel checked -> build/osd_test/osd_*.png
# The PS7 needs the congestion-driven placer (soc/openxc7.py PNR_OPTS). Takes the container lock like hdmi-test.
OSD_TEST_V := rtl/board/osd_test_top.v rtl/board/osd_test_core.v rtl/board/osd_banner.v rtl/board/hdmi_pattern.v \
	rtl/glass/zm_glass_regs.v rtl/glass/zm_glass_ptr.v rtl/glass/zm_glass_osd.v rtl/video/zm_video_dcram.v \
	rtl/video/zm_vtiming.v $(HDMI_SER_V)

.PHONY: osd-test osd-test-sim

build/osd_test/osd_test_top.xdc: rtl/board/osd_test_top.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

build/osd_test/osd_test_top.bit: $(OSD_TEST_V) gen/memmap.vh gen/glass_map.vh gen/glass_font.vh build/osd_test/osd_test_top.xdc
	OPENXC7_PNR_OPTS="--placer-heap-congestion-spread" $(HDMI_LOCK) tools/openxc7.sh bit osd_test_top \
		$(CURDIR)/$(@D) $(CURDIR)/$(@D)/osd_test_top.xdc $(addprefix $(CURDIR)/,$(OSD_TEST_V))

osd-test: build/osd_test/osd_test_top.bit

osd-test-sim: memmap
	uv run python tools/osd_test_sim.py

#   make ym-test   fifth: the YM2149 (jt49, the audio core) playing "Drooling" by 505 from a register dump in
#                  BRAM, 44.1 kHz over HDMI with the test pattern -> build/ym_test/ym_test_top.bit
#                  (docs/FPGA_AUDIO.md). Simulated against the Zig machine by `make test` (tests/test_rtl_audio.py).
YM_TUNE   := $(ROOT)/docs/music/union/Drooling.ymraw
YM_TEST   := build/ym_test
YM_TEST_V := $(addprefix rtl/board/,ym_test_top.v ym_test_clk.v ym_test_core.v ym_test_audio.v snd_lab_out.v \
	zm_dump_player.v hdmi_pattern.v) rtl/video/zm_vtiming.v $(wildcard rtl/audio/zm_audio_*.v) \
	$(wildcard rtl/hdmi/zm_hdmi_*.v) $(wildcard third_party/jt49/hdl/jt49*.v) \
	rtl/video/zm_dvi_out.v rtl/video/zm_tmds_enc.v rtl/video/zm_tmds_shift.v

.PHONY: ym-test

# The ROM sits where the container's yosys runs, so ym_test_audio's default path finds it.
$(YM_TEST)/ym_rom.hex: $(YM_TUNE) tools/ym_rom.py
	@mkdir -p $(@D)
	uv run python tools/ym_rom.py $< $@

$(YM_TEST)/ym_test_top.xdc: rtl/board/ym_test_top.v $(BOARD_XDC)
	@mkdir -p $(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) $< > $@
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $@

$(YM_TEST)/ym_test_top.bit: $(YM_TEST_V) gen/memmap.vh $(YM_TEST)/ym_test_top.xdc $(YM_TEST)/ym_rom.hex
	OPENXC7_DEFS="-defer -DYM_WORDS=$$(wc -l < $(YM_TEST)/ym_rom.hex)" $(HDMI_LOCK) tools/openxc7.sh bit \
		ym_test_top $(CURDIR)/$(@D) $(CURDIR)/$(@D)/ym_test_top.xdc $(addprefix $(CURDIR)/,$(YM_TEST_V))

ym-test: $(YM_TEST)/ym_test_top.bit

# --- the first cart on the board: main RAM + video DMA in PS DDR over HP0/HP1 (cycles/board.mk) ---
#   make hp-sim CART=tutorial    the board SoC with a model of the PS, in Verilator: hashes vs scene_hash
#   make board-fw CART=tutorial  the firmware image U-Boot loads (fpga/boards/microphase_z7_7010/README.md)
include cycles/audio.mk
include cycles/board.mk
include cycles/sound.mk
include cycles/split.mk

# --- the edit -> board loop: release / dev (placement replay) builds, seed sweeps, hp-test (flow.mk) ---
include flow.mk
