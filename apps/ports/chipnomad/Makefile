# ChipNomad (Megus, MIT, C++17) for the ZigMachine / KESTREL, as a C++ cart. Upstream untouched in
# ../upstream/chipnomad-tracker (apps/ports/fetch.sh), mirrored into build/gen and patched there by patches/<file>.sed (must change its file).
# Its platform layer is replaced by kestrel_corelib.cpp (no SDL renderer at all); the shared
# ../kestrel_sdl2 layer supplies the heap, WASI over the floppy and the key exports.
#   make link | make install | make clean
WABT   ?= ../../../fpga/.tools/wabt/bin
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
UPSTREAM ?= ../upstream
UP     := $(UPSTREAM)/chipnomad-tracker
# tracker/src/version.cpp shows __DATE__ as the build: pinned to the upstream commit's date, so a rebuild
# reproduces docs/demo-chipnomad.wasm byte for byte (SOURCE_DATE_EPOCH is not in zig cc's cache key).
BUILD_DATE := $(shell git -C $(UP) log -1 --format=%cd --date=format:'%b %e %Y')
OUT    := build
GEN    := $(OUT)/gen
KSDL   := ../kestrel_sdl2/src
KINC   := ../kestrel_sdl2/include
# upstream's source dirs (Makefile.common COMMON_LIBS), minus platforms/shared (main.cpp, big fonts) and the SDL2 back end;
# platforms/sdl2/corelib_input.cpp is kept: its key mapping and key names are platform-independent here.
DIRS   := tracker/src chipnomad_lib chipnomad_lib/chips chipnomad_lib/external/ayumi chipnomad_lib/export \
          tracker/src/corelib tracker/src/import tracker/src/screens
UP_ALL := $(foreach d,$(DIRS),$(patsubst $(UP)/%,%,$(wildcard $(UP)/$(d)/*.c $(UP)/$(d)/*.cpp $(UP)/$(d)/*.h))) \
          tracker/platforms/sdl2/corelib_input.cpp tracker/platforms/shared/corelib_keymap.h
UP_SRC := $(filter %.c %.cpp,$(UP_ALL))
INCS   := $(addprefix -I$(GEN)/,$(DIRS) tracker/platforms/shared tracker/platforms/sdl2) -I$(KINC) -I$(KINC)/SDL2
FLAGS  := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory $(INCS) -include kestrel_port.h -D__KESTREL__ -Wno-unused-parameter -Wno-date-time \
          -Wno-builtin-macro-redefined '-D__DATE__="$(BUILD_DATE)"'
CXXFLAGS := $(FLAGS) -std=c++17 -fno-exceptions -fno-rtti
CFLAGS := $(FLAGS) -std=gnu11
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=262144 -Wl,--strip-debug
OBJS   := $(patsubst %,$(OUT)/up/%.o,$(UP_SRC)) $(patsubst %,$(OUT)/%.o,$(wildcard kestrel_*.cpp)) \
          $(patsubst $(KSDL)/%.c,$(OUT)/ksdl/%.o,$(wildcard $(KSDL)/*.c))
GENALL := $(addprefix $(GEN)/,$(UP_ALL))

.PHONY: link objs clean install
.SECONDARY:
objs: $(OBJS)
$(GEN)/%: $(UP)/% $(wildcard patches/*.sed)
	@mkdir -p $(dir $@)
	@if [ -f patches/$(notdir $*).sed ]; then sed -f patches/$(notdir $*).sed $< > $@; \
	  ! cmp -s $< $@ || { echo "patch $* changed nothing"; rm $@; exit 1; }; else cp $< $@; fi
$(OUT)/up/%.cpp.o: $(GEN)/%.cpp $(GENALL)
	@mkdir -p $(dir $@)
	$(ZIG) c++ $(CXXFLAGS) -c $< -o $@
$(OUT)/up/%.c.o: $(GEN)/%.c $(GENALL)
	@mkdir -p $(dir $@)
	$(ZIG) c++ -x c++ $(CXXFLAGS) -c $< -o $@
$(OUT)/%.cpp.o: %.cpp $(GENALL)
	@mkdir -p $(dir $@)
	$(ZIG) c++ $(CXXFLAGS) -c $< -o $@
$(OUT)/ksdl/%.o: $(KSDL)/%.c
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@

link: $(OUT)/demo-chipnomad.wasm
$(OUT)/demo-chipnomad.wasm: $(OBJS)
	$(ZIG) c++ $(CXXFLAGS) $(LDFLAGS) $^ -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c

clean:
	rm -rf $(OUT)

# The shipped cart: docs/demo-chipnomad.wasm, committed prebuilt (build.sh does not rebuild the C ports).
# tools/mkdisks.sh (the one recipe for the disk) packs docs/demo-chipnomad.zmd from it.
install: $(OUT)/demo-chipnomad.wasm
	cp $< ../../../docs/demo-chipnomad.wasm
	cd ../../.. && tools/mkdisks.sh
