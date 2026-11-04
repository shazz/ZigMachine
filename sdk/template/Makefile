# A KESTREL cart (docs/SDK.md). Copy this directory, rename NAME, edit src/hello.zig.
#   make            build, then serve the browser emulator with the cart (Ctrl-C stops it)
#   make cart       build only: zig-out/demo-$(NAME).wasm
#   make floppy     the cart on a disk: zig-out/demo-$(NAME).zmd (FILES="A.RAW=path ..." adds files)
#   make board      the board image (zig-out/board/$(NAME)/cart.bin) and the SD folder zig-out/sd
#   make doctor     check every tool the SDK needs
#   make clean      also removes the cart's copies from the SDK's docs/
NAME    ?= hello
TITLE   ?= HELLO KESTREL
AUTHOR  ?= $(USER)
GROUP   ?=
YEAR    ?= $(shell date +%Y)
DESC    ?= My first KESTREL cart
CATEGORY ?= demos
FILES   ?=
PORT    ?= 3333
ZIG     ?= zig
PYTHON  ?= python3

# The SDK: the path build.zig.zon gives the kestrel dependency (one place to change it).
KESTREL := $(abspath $(shell sed -n 's/.*\.kestrel = \.{ *\.path = "\([^"]*\)".*/\1/p' build.zig.zon))
ifeq ($(wildcard $(KESTREL)/build.zig),)
$(error no SDK at '$(KESTREL)': fix the .kestrel path in build.zig.zon)
endif
# The SD card of the SDK release, if this SDK came as one (kestrel-sdk-<v>/card, RELEASE.txt).
CARD    ?= $(wildcard $(KESTREL)/../card)
RELEASE ?= $(wildcard $(KESTREL)/../RELEASE.txt)

OUT  := zig-out
WASM := $(OUT)/demo-$(NAME).wasm
ZMD  := $(OUT)/demo-$(NAME).zmd
DOCS := $(KESTREL)/docs

.PHONY: run cart floppy board doctor clean install-docs
run: install-docs
	@echo "== http://localhost:$(PORT)/sealed.html?disk=demo-$(NAME).zmd   (boots like the machine: POST, then the disk)"
	@echo "== http://localhost:$(PORT)/sealed.html?demo=demo-$(NAME).wasm  (the cart straight away)"
	cd $(KESTREL) && ./serve.sh $(PORT)

cart:
	$(ZIG) build -Dname=$(NAME)

$(ZMD): cart
	$(OUT)/bin/zx0pack $(WASM) $(OUT)/demo-$(NAME).zx0 >/dev/null
	$(PYTHON) $(KESTREL)/tools/mkdisk.py $(OUT)/demo-$(NAME).zx0 -o $@ --title "$(TITLE)" --author "$(AUTHOR)" \
		--desc "$(DESC)" --date $$(date +%Y%m%d) $(foreach f,$(FILES),--file $(f))
	rm -f $(OUT)/demo-$(NAME).zx0
floppy: $(ZMD)

# The browser emulator and the board build both read the SDK's docs/demo-<tag>.*: put ours there,
# but never over one of the SDK's own carts (a marker in docs/.sdk/ says the file is ours).
install-docs: $(ZMD)
	@if [ -e $(DOCS)/demo-$(NAME).wasm ] && [ ! -e $(DOCS)/.sdk/$(NAME) ]; then \
		echo "error: '$(NAME)' is one of the SDK's own carts: pick another NAME"; exit 1; fi
	mkdir -p $(DOCS)/.sdk && touch $(DOCS)/.sdk/$(NAME)
	cp $(WASM) $(ZMD) $(DOCS)/

# --- the board ---------------------------------------------------------------
# The riscv gcc: the first of these prefixes on PATH (Ubuntu / Arch / xPack and macOS).
RV_PREFIX ?= $(firstword $(foreach p,riscv64-unknown-elf- riscv64-elf- riscv-none-elf-,$(if $(shell command -v $(p)gcc 2>/dev/null),$(p))))
RV_CC  := $(RV_PREFIX)gcc
# Headers: picolibc's when the gcc has it (what the repo's own board builds use), else the gcc's
# own newlib ones. The cart links NO libc (-nostdlib), only the helpers below.
PICOLIBC := $(shell echo | $(RV_CC) --specs=picolibc.specs -march=rv32im -mabi=ilp32 -E - >/dev/null 2>&1 && echo yes)
RV_ARCH  := -march=rv32im -mabi=ilp32 $(if $(PICOLIBC),--specs=picolibc.specs)
# libgcc for rv32imf/ilp32f when the gcc has that multilib; else Zig's compiler_rt, built by zig build.
RV_MULTI := $(shell $(RV_CC) -march=rv32imf -mabi=ilp32f -print-multi-directory 2>/dev/null)
ZRT := $(OUT)/rt/zrt_cart.o
CART_RTLIB := $(if $(filter rv32imf/ilp32f,$(RV_MULTI)),-lgcc,$(abspath $(ZRT)))
# wabt (wasm2c and its runtime headers): the SDK's own copy if `tools/sdk_doctor.sh --fetch-wabt` made one,
# else the one on PATH (Arch / Homebrew / a release tarball).
WABT ?= $(if $(wildcard $(KESTREL)/fpga/.tools/wabt/bin/wasm2c),$(KESTREL)/fpga/.tools/wabt,$(abspath $(dir $(shell command -v wasm2c))..))
BOARD_FLAGS := ZM_AUDIO=snd ZM_FPU=1 ZM_ZMX=1 CART=$(NAME) CARTS_DIR=$(abspath $(OUT)/board) \
	RV_CC=$(RV_CC) RV_OBJCOPY=$(RV_PREFIX)objcopy RV_AR=$(RV_PREFIX)ar RV_ARCH="$(RV_ARCH)" \
	CART_RTLIB="$(CART_RTLIB)" WABT=$(WABT) ZIG=$(shell command -v $(ZIG))

# compiler_rt trimmed to libgcc's helpers, no .data, no C instructions (sdk/zrt_cart.sh says why).
$(ZRT): cart
	$(KESTREL)/sdk/zrt_cart.sh $(RV_PREFIX) $(OUT)/rt/zrt.o $@

board: install-docs $(if $(filter -lgcc,$(CART_RTLIB)),,$(ZRT))
	@[ -n "$(RV_PREFIX)" ] || { echo "error: no riscv gcc on PATH (tools/sdk_doctor.sh says which to install)"; exit 1; }
	@echo "== riscv: $(RV_CC), headers $(if $(PICOLIBC),picolibc,newlib), runtime $(notdir $(CART_RTLIB))"
	UV_NO_PROJECT=1 $(MAKE) -C $(KESTREL)/fpga memmap split-cart $(BOARD_FLAGS)
	$(PYTHON) $(KESTREL)/sdk/card.py --tag $(NAME) --cart $(OUT)/board/$(NAME)/cart.bin --disk $(ZMD) \
		--zx0pack $(OUT)/bin/zx0pack --out $(OUT)/sd --category $(CATEGORY) --title "$(TITLE)" \
		--group "$(GROUP)" --year "$(YEAR)" --desc "$(DESC)" \
		$(if $(CARD),--card $(CARD)) $(if $(RELEASE),--release $(RELEASE))

doctor:
	$(KESTREL)/tools/sdk_doctor.sh

# Also takes our copies back out of the SDK's docs/ (only ours: the marker says which).
clean:
	rm -rf $(OUT) .zig-cache
	if [ -e $(DOCS)/.sdk/$(NAME) ]; then rm -f $(DOCS)/demo-$(NAME).wasm $(DOCS)/demo-$(NAME).zmd $(DOCS)/.sdk/$(NAME); fi
