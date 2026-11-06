# GrafX2 (GPLv2, the GrafX2 team) for the ZigMachine / KESTREL, as a C cart. Same layout as
# apps/ports/pt2: upstream untouched in ../upstream/grafX2 (apps/ports/fetch.sh), mirrored into build/gen/ and
# patched there by patches/<file>.sed (a patch must change its file), the shared SDL2 layer in ../kestrel_sdl2.
#   make objs | make link | make install | make clean
WABT   ?= ../../../fpga/.tools/wabt/bin
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
UPSTREAM ?= ../upstream
UP     := $(UPSTREAM)/grafX2/src
OUT    := build
GEN    := $(OUT)/gen
KSDL   := ../kestrel_sdl2/src
KINC   := ../kestrel_sdl2/include
# Upstream's SDL2 backend (sdlscreen.c), without TrueType, Lua, recoil, libpng and libtiff.
DEFS   := -DUSE_SDL2 -DNOTTF=1 -DNOLUA=1 -DNORECOIL -D__no_pnglib__ -D__no_tifflib__ -D__KESTREL__ -DKESTREL_CDRIVE
CFLAGS := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory -std=gnu11 -I$(KINC) -I$(KINC)/SDL2 -Iinclude -I$(GEN) -include kestrel_port.h $(DEFS) \
          -Wno-unused-parameter -Wno-unused-but-set-variable
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=262144 -Wl,--strip-debug

# upstream src/Makefile's OBJS for the sdl2 API, minus loadrecoil/recoil (NORECOIL); version.c is generated.
UP_OBJS := main init graph sdlscreen misc osdep special buttons palette help operatio pages readline engine \
  filesel fileseltools op_c readini saveini shade keyboard io pversion text SFont setup pxsimple pxtall pxwide \
  pxdouble pxtriple pxtall2 pxtall3 pxwide2 pxquad windows brush realpath mountlist input hotkeys transform \
  factory loadsave loadsavefuncs pngformat motoformats stformats c64formats cpcformats ifformat msxformats \
  packbits giformat 2gsformats packbytes fileformats miscfileformats libraw2crtc brush_ops buttons_effects \
  layers oldies tiles colorred unicode gfx2surface gfx2log gfx2mem tifformat
UP_ALL := $(patsubst $(UP)/%,%,$(wildcard $(UP)/*.[ch]))
# C: (KOS GEMDOS, docs/KOS_GEMDOS.md): the POSIX layer's "/C" (KESTREL_CDRIVE above) over GEMDOS's object.
CDRIVE := $(OUT)/ksdl/opt/kestrel_wasi_c.o $(OUT)/ksdl/opt/kestrel_wasi_cdir.o $(OUT)/gemdos.o
OBJS   := $(addprefix $(OUT)/,$(addsuffix .o,$(UP_OBJS) version)) \
          $(patsubst %.c,$(OUT)/%.o,$(wildcard kestrel_*.c)) $(patsubst $(KSDL)/%.c,$(OUT)/ksdl/%.o,$(wildcard $(KSDL)/*.c)) $(CDRIVE)
GENALL := $(addprefix $(GEN)/,$(UP_ALL)) $(GEN)/version.c

.PHONY: objs link clean install
.SECONDARY:
objs: $(OBJS)

$(GEN)/version.c:
	@mkdir -p $(dir $@)
	echo 'const char SVN_revision[]="$(shell git -C $(UPSTREAM)/grafX2 log -1 --format=%h)";' > $@
$(GEN)/%: $(UP)/% $(wildcard patches/*.sed)
	@mkdir -p $(dir $@)
	@if [ -f patches/$(notdir $*).sed ]; then sed -f patches/$(notdir $*).sed $< > $@; \
	  ! cmp -s $< $@ || { echo "patch $* changed nothing"; rm $@; exit 1; }; else cp $< $@; fi
# KOS GEMDOS, built from the ROM tree's Zig (rom/kos/gemdos_c.zig and the reader it sits on).
GEMDOS := ../../../rom/kos
$(OUT)/gemdos.o: $(wildcard $(GEMDOS)/gemdos*.zig $(GEMDOS)/fat*.zig)
	@mkdir -p $(dir $@)
	$(ZIG) build-obj -target wasm32-wasi -OReleaseSmall -fno-stack-check $(GEMDOS)/gemdos_c.zig -femit-bin=$@
$(OUT)/ksdl/opt/%.o: $(KSDL)/opt/%.c $(KSDL)/opt/kestrel_wasi_c.h $(wildcard $(KINC)/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(wildcard $(KINC)/*.h $(KINC)/SDL2/*)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/kestrel_%.o: kestrel_%.c $(wildcard $(KINC)/*.h $(KINC)/SDL2/*)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/%.o: $(GEN)/%.c $(GENALL)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@

# Asyncify: GrafX2 blocks in its own loops; kestrel_main.c suspends it in SDL_Delay (see there).
WASM_OPT := node $(UPSTREAM)/binaryen/bin/wasm-opt
link: $(OUT)/demo-grafx2.wasm
$(OUT)/demo-grafx2.raw.wasm: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(LDFLAGS) $^ -o $@
$(OUT)/demo-grafx2.wasm: $(OUT)/demo-grafx2.raw.wasm
	$(WASM_OPT) $< --enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int \
	  --asyncify -O2 -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c

clean:
	rm -rf $(OUT)

# The shipped cart: docs/demo-grafx2.wasm, committed prebuilt (build.sh does not rebuild the C ports).
# tools/mkdisks.sh (the one recipe for the disk) packs docs/demo-grafx2.zmd from it plus data/ (the default
# skin and font as GIF, gfx2def.ini) and ownpics/ (our own plasma art as PI1, NEO and GIF). Pictures ripped
# from other people's work never go on it.
install: $(OUT)/demo-grafx2.wasm
	cp $< ../../../docs/demo-grafx2.wasm
	cd ../../.. && tools/mkdisks.sh
