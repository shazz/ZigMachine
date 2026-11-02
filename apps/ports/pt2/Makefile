# pt2-clone (8bitbubsy, BSD-3) for the ZigMachine / KESTREL, as a C cart.
#   make link    build build/demo-pt2.wasm, then list its imports (a cart may import only "env")
#   make objs    compile only;  make clean
#   make EXTRA=-DHEAP_TRACE link   log every malloc >= 16 KB
#   make install  copy the cart to docs/ and repack its disk (tools/mkdisks.sh)
# Upstream stays untouched in ../upstream/pt2-clone (apps/ports/fetch.sh clones it at its pinned commit).
# Every upstream source is mirrored into build/gen/ (so quoted includes find the patched headers) and
# patched there by patches/<file>.sed when one exists; a patch must change its file or the build stops. KESTREL code lives here (kestrel_*) and in ../kestrel_sdl2.
WABT   ?= ../../../fpga/.tools/wabt/bin
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
UP     ?= ../upstream
PT2    := $(UP)/pt2-clone/src
OUT    := build
GEN    := $(OUT)/gen
CFLAGS := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory -std=gnu11 -I../kestrel_sdl2/include -include kestrel_port.h \
          -D__KESTREL__ -Wno-unused-parameter -Wno-unused-but-set-variable
# The cart's memory layout, as apps/c/build.sh: the machine's one memory, data from 0x100000.
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=262144 -Wl,--strip-debug

UP_ALL := $(patsubst $(PT2)/%,%,$(wildcard $(PT2)/*.[ch] $(PT2)/modloaders/*.[ch] $(PT2)/smploaders/*.[ch] $(PT2)/gfx/*.[ch]))
# pt2_main.c (SDL main loop, signals, argv) is split by split_main.py into pt2_boot()/pt2_frame().
UP_C   := $(filter %.c,$(UP_ALL))
# The shared KESTREL SDL2 layer (apps/ports/kestrel_sdl2/src: heap, WASI-on-floppy, input) + this port's kestrel_*.c.
KSDL   := ../kestrel_sdl2/src
OBJS   := $(addprefix $(OUT)/,$(UP_C:.c=.o)) $(patsubst %.c,$(OUT)/%.o,$(wildcard kestrel_*.c)) $(patsubst $(KSDL)/%.c,$(OUT)/ksdl/%.o,$(wildcard $(KSDL)/*.c))
GENALL := $(addprefix $(GEN)/,$(UP_ALL))

.PHONY: objs link clean install
.SECONDARY:
objs: $(OBJS)

$(GEN)/pt2_main.c: $(PT2)/pt2_main.c split_main.py
	@mkdir -p $(dir $@)
	python3 split_main.py $< $@
$(GEN)/%: $(PT2)/% $(wildcard patches/*.sed)
	@mkdir -p $(dir $@)
	@if [ -f patches/$(notdir $*).sed ]; then sed -f patches/$(notdir $*).sed $< > $@; \
	  ! cmp -s $< $@ || { echo "patch $* changed nothing"; rm $@; exit 1; }; else cp $< $@; fi
$(OUT)/kestrel_%.o: kestrel_%.c kestrel_port.h $(wildcard ../kestrel_sdl2/include/*.h ../kestrel_sdl2/include/SDL2/*)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(wildcard ../kestrel_sdl2/include/*.h ../kestrel_sdl2/include/SDL2/*)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/%.o: $(GEN)/%.c $(GENALL) kestrel_port.h
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@

link: $(OUT)/demo-pt2.wasm
$(OUT)/demo-pt2.wasm: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(LDFLAGS) $^ -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c

clean:
	rm -rf $(OUT)

# The shipped cart: docs/demo-pt2.wasm, committed prebuilt (build.sh does not rebuild the C ports).
# tools/mkdisks.sh (the one recipe for the disk) packs docs/demo-pt2.zmd from it plus RONKEN.MOD and
# HYBRID.MOD (docs/music/ronken.mod, hybridglenz.mod).
install: $(OUT)/demo-pt2.wasm
	cp $< ../../../docs/demo-pt2.wasm
	cd ../../.. && tools/mkdisks.sh
