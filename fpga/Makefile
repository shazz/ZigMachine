# ZigMachine on an FPGA. Every target runs from fpga/; see README.md.
#   make setup     cores, Python env, sv2v + wasm2c (once)
#   make check     memmap + tests + SoC elaboration: the fpga/ gate
#   make util      LUT/FF/BRAM/DSP of each block on the 7-series
#   make carts     plan step 0a: every cart -> wasm2c -> rv32imf
ZIG      ?= $(HOME)/.local/zig/0.16.0/zig
ROOT     := $(abspath ..)
MEMMAP   := $(ROOT)/machine/sdk/memmap.zig
EXPORT   := tools/memmap_export.zig
export PATH := $(CURDIR)/.tools/bin:$(CURDIR)/.tools/wabt/bin:$(PATH)

.PHONY: setup memmap test soc check util carts clean

setup:
	tools/setup.sh

gen/memmap.vh gen/memmap.py: $(MEMMAP) $(EXPORT)
	@mkdir -p gen
	$(ZIG) run --dep memmap -Mroot=$(EXPORT) -Mmemmap=$(MEMMAP) -- verilog gen/memmap.vh
	$(ZIG) run --dep memmap -Mroot=$(EXPORT) -Mmemmap=$(MEMMAP) -- python gen/memmap.py

memmap: gen/memmap.vh gen/memmap.py

test: memmap
	uv run pytest -q

soc: memmap
	uv run python -m soc.zigmachine_soc --target sim

check: test soc
	@echo "fpga: check passed"

util: memmap
	uv run python tools/util.py

carts:
	tools/wasm2rv.sh

clean:
	rm -rf build gen
