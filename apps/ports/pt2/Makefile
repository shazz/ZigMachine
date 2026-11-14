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
# KESTREL_CDRIVE: the POSIX layer's "/C" (C: = the card's HD, KOS GEMDOS, docs/KOS_GEMDOS.md §5), see CDRIVE below.
CFLAGS := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory -std=gnu11 -I../kestrel_sdl2/include -include kestrel_port.h \
          -D__KESTREL__ -DKESTREL_CDRIVE -Wno-unused-parameter -Wno-unused-but-set-variable
# The cart's memory layout, as apps/c/build.sh: the machine's one memory, data from 0x100000.
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=262144 -Wl,--strip-debug

UP_ALL := $(patsubst $(PT2)/%,%,$(wildcard $(PT2)/*.[ch] $(PT2)/modloaders/*.[ch] $(PT2)/smploaders/*.[ch] $(PT2)/gfx/*.[ch]))
# pt2_main.c (SDL main loop, signals, argv) is split by split_main.py into pt2_boot()/pt2_frame().
# pt2_paula.c (double-precision BLEP mixer) is replaced by kestrel_paula.c (integer, same API).
UP_C   := $(filter-out pt2_paula.c,$(filter %.c,$(UP_ALL)))
# The shared KESTREL SDL2 layer (apps/ports/kestrel_sdl2/src: heap, WASI-on-floppy, input) + this port's kestrel_*.c.
KSDL   := ../kestrel_sdl2/src
# C: (KOS GEMDOS): the WASI entry points for "/C" and C:'s files (src/opt/kestrel_wasi_c*.c) over GEMDOS's object,
# built from the ROM tree's Zig (rom/kos/gemdos_c.zig and the reader it sits on), as apps/ports/grafx2/Makefile.
CDRIVE := $(OUT)/ksdl/opt/kestrel_wasi_c.o $(OUT)/ksdl/opt/kestrel_wasi_cdir.o $(OUT)/ksdl/opt/kestrel_wasi_cfile.o $(OUT)/gemdos.o
GEMDOS := ../../../rom/kos
OBJS   := $(addprefix $(OUT)/,$(UP_C:.c=.o)) $(patsubst %.c,$(OUT)/%.o,$(wildcard kestrel_*.c)) $(patsubst $(KSDL)/%.c,$(OUT)/ksdl/%.o,$(wildcard $(KSDL)/*.c)) $(CDRIVE)
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
# kestrel_paula.c implements pt2_paula.h, kestrel_paula_hw.c drives the hardware channels (HW 1.14.0):
# they read upstream's (mirrored) headers.
$(OUT)/kestrel_paula.o $(OUT)/kestrel_paula_hw.o: CFLAGS += -I$(GEN)
$(OUT)/kestrel_paula.o $(OUT)/kestrel_paula_hw.o: $(GENALL)
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(wildcard ../kestrel_sdl2/include/*.h ../kestrel_sdl2/include/SDL2/*)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/opt/%.o: $(KSDL)/opt/%.c $(KSDL)/opt/kestrel_wasi_c.h $(wildcard ../kestrel_sdl2/include/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/gemdos.o: $(wildcard $(GEMDOS)/gemdos*.zig $(GEMDOS)/fat*.zig)
	@mkdir -p $(dir $@)
	$(ZIG) build-obj -target wasm32-wasi -OReleaseSmall -fno-stack-check $(GEMDOS)/gemdos_c.zig -femit-bin=$@
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
