# klystrack (kometbomb, MIT) for the ZigMachine / KESTREL, as a C cart. Same layout as prototypes/pt2clone/port
# and apps/ports/grafx2: upstream untouched in ../upstream/klystrack (apps/ports/fetch.sh; klystron, its submodule,
# at ../upstream/klystrack/klystron), every upstream
# source mirrored into build/gen/ and patched there by patches/<file>.sed when one exists (a patch must change
# its file or the build stops; upstream's CRLF line ends are dropped first). The shared SDL2 layer is ../kestrel_sdl2 (src/*.c always, plus the
# opt-in modules in src/opt/: RWops, software renderer, timers/mutexes, stb_image IMG_Load).
#   make objs | make link | make data | make install | make clean
WABT   ?= ../../../fpga/.tools/wabt/bin
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
UPSTREAM ?= ../upstream
UP     := $(UPSTREAM)/klystrack
OUT    := build
GEN    := $(OUT)/gen
KSDL   := ../kestrel_sdl2/src
KINC   := ../kestrel_sdl2/include
# upstream's EXTFLAGS minus MIDI (ALSA + a thread); the window is 320x240 at scale 1 (patches/mused.c.sed).
DEFS   := -DNOSDL_MIXER -DUSESDLMUTEXES -DSTEREOOUTPUT -DUSESDL_IMAGE -DUSESDL_RWOPS -DCONFIG_DEFAULT_DISABLE_RENDER_TO_TEXTURE \
          -DLOWRESWAVETABLE -DRES_PATH= -DCONFIG_PATH=/klystrack.cfg -DKLYSTRON=klystron -D__KESTREL__ -DKESTREL_SDL_IMAGE -DKESTREL_HEAP_ROVER
CFLAGS := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory -std=gnu11 -I$(KINC) -I$(KINC)/SDL2 \
          -I$(GEN)/src -I$(GEN)/klystron -include kestrel_port.h $(DEFS) \
          -Wno-unused-parameter -Wno-unused-but-set-variable \
          -Wno-pointer-sign -Wno-deprecated-non-prototype
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=131072 -Wl,--strip-debug

# Sources: klystron's engine (gfx, gui, snd, util; not lib/, the standalone player library) and klystrack's
# src/ with import/ and view/, minus midi.c (ALSA, built only with -DMIDI).
KLY_C  := $(patsubst $(UP)/klystron/src/%,klystron/%,$(wildcard $(UP)/klystron/src/gfx/*.c $(UP)/klystron/src/gui/*.c $(UP)/klystron/src/snd/*.c $(UP)/klystron/src/util/*.c))
APP_C  := $(filter-out src/midi.c,$(patsubst $(UP)/%,%,$(wildcard $(UP)/src/*.c $(UP)/src/import/*.c $(UP)/src/view/*.c)))
UP_H   := $(patsubst $(UP)/klystron/src/%,klystron/%,$(wildcard $(UP)/klystron/src/*.h $(UP)/klystron/src/*/*.h)) \
          $(patsubst $(UP)/%,%,$(wildcard $(UP)/src/*.h $(UP)/src/*/*.h))
KOPT   := $(wildcard $(KSDL)/opt/*.c)
OBJS   := $(addprefix $(OUT)/,$(KLY_C:.c=.o) $(APP_C:.c=.o)) $(patsubst %.c,$(OUT)/%.o,$(wildcard kestrel_*.c)) \
          $(patsubst $(KSDL)/%.c,$(OUT)/ksdl/%.o,$(wildcard $(KSDL)/*.c) $(KOPT))
GENALL := $(addprefix $(GEN)/,$(KLY_C) $(APP_C) $(UP_H)) $(GEN)/src/version.h $(GEN)/src/version_number.h $(GEN)/klystron/version.h
SHIMH  := $(wildcard $(KINC)/*.h $(KINC)/SDL2/* $(KSDL)/opt/*.h)

.PHONY: objs link data clean install names
comma := ,
.SECONDARY:
objs: $(OBJS)

$(GEN)/src/version_number.h: $(UP)/src/version
	@mkdir -p $(dir $@)
	printf '#ifndef VERSION_NUMBER\n#define VERSION_NUMBER\n#define VERSION "%s"\n#endif\n' "$$(tr -d '\r\n' < $<)" > $@
$(GEN)/src/version.h:
	@mkdir -p $(dir $@)
	printf '#ifndef VERSION_H\n#define VERSION_H\n#include "version_number.h"\n#define REVISION "%s-kestrel"\n#define VERSION_STRING "klystrack " VERSION " " REVISION\n#endif\n' "$$(git -C $(UP) log -1 --format=%h)" > $@
$(GEN)/klystron/version.h:
	@mkdir -p $(dir $@)
	printf '#ifndef KLYSTRON_VERSION_H\n#define KLYSTRON_VERSION_H\n#define KLYSTRON_REVISION "%s"\n#define KLYSTRON_VERSION_STRING "klystron " KLYSTRON_REVISION\n#endif\n' "$$(git -C $(UP)/klystron log -1 --format=%h)" > $@
define mirror
	@mkdir -p $(dir $@)
	@tr -d '\r' < $< > $@.lf
	@if [ -f patches/$(notdir $<).sed ]; then sed -f patches/$(notdir $<).sed $@.lf > $@; \
	  ! cmp -s $@.lf $@ || { echo "patch $(notdir $<) changed nothing"; rm $@ $@.lf; exit 1; }; else cp $@.lf $@; fi
	@rm -f $@.lf
endef
$(GEN)/klystron/%: $(UP)/klystron/src/% $(wildcard patches/*.sed)
	$(mirror)
$(GEN)/src/%: $(UP)/src/% $(wildcard patches/*.sed)
	$(mirror)
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(SHIMH)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/kestrel_%.o: kestrel_%.c kestrel_port.h $(SHIMH)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/%.o: $(GEN)/%.c $(GENALL) kestrel_port.h $(SHIMH)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@

# Asyncify (as GrafX2): klystrack blocks in its main loop and its dialogs; kestrel_main.c suspends it in
# SDL_Delay and SDL_RenderPresent and resumes it each frame().
WASM_OPT := node $(UPSTREAM)/binaryen/bin/wasm-opt
link: $(OUT)/demo-klystrack.wasm
$(OUT)/demo-klystrack.raw.wasm: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(LDFLAGS) $^ -o $@
$(OUT)/demo-klystrack.wasm: $(OUT)/demo-klystrack.raw.wasm
	$(WASM_OPT) $< --enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int \
	  --asyncify -O2 -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c

# The same cart with its function names (no --strip-debug, wasm-opt -g), for apps/frame_cost.mjs and
# tools/perf_audit.sh: `node apps/frame_cost.mjs apps/ports/klystrack/build/names/demo-klystrack.wasm --disk docs/demo-klystrack.zmd`
names: $(OUT)/names/demo-klystrack.wasm
$(OUT)/names/demo-klystrack.wasm: $(OBJS)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) $(filter-out -Wl$(comma)--strip-debug,$(LDFLAGS)) $^ -o $(OUT)/names/raw.wasm
	$(WASM_OPT) $(OUT)/names/raw.wasm --enable-bulk-memory --enable-sign-ext --enable-mutable-globals \
	  --enable-nontrapping-float-to-int --asyncify -O2 -g -o $@

clean:
	rm -rf $(OUT)

# The floppy's files, committed in data/ so tools/mkdisks.sh (the one recipe for the disk) packs
# docs/demo-klystrack.zmd without an upstream checkout: the Default theme as one bundle file (mkbundle.py;
# klystrack opens "<RES_PATH>/res/Default", which the flat floppy FS matches on its last component) and
# example songs from upstream's examples/songs, renamed to the floppy's 16-character names. STARPORT2.KT is
# opened at boot (kestrel_main.c argv[1]). `make data` regenerates them from upstream.
# (an upstream name's '+' stands for a space: "Ocean Loader III.kt")
SONGS := STARPORT2.KT:Starport2.kt CASTLEVANIA.KT:castlevania.kt OCEANLOADER3.KT:Ocean+Loader+III.kt DPINTRO.KT:smp_dpintro.kt
data: mkbundle.py
	@mkdir -p data
	python3 mkbundle.py $(UP)/themes/Default data/Default
	set -e; for s in $(SONGS); do n=$${s%%:*}; f=$$(echo "$${s#*:}" | tr + ' '); \
	  cp "$(UP)/examples/songs/$$f" data/$$n; done

# The shipped cart: docs/demo-klystrack.wasm, committed prebuilt (build.sh does not rebuild the C ports).
install: $(OUT)/demo-klystrack.wasm
	cp $< ../../../docs/demo-klystrack.wasm
	cd ../../.. && tools/mkdisks.sh
